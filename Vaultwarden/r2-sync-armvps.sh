# POSIX sh compatible - Vaultwarden Sync with GPG Encryption + Backups

RCLONE_CONFIG="/usr/share/vaultwarden/rclone-armvps.conf"
VW_DATA="/usr/share/vaultwarden"
REMOTE_NAME="r2:vaultwarden-armvps"
VAULTWARDEN_CONTAINER="vaultwarden"

DB_FILE="$VW_DATA/vw-data/db.sqlite3"
DB_FILES_TO_SYNC="db.sqlite3 db.sqlite3-shm db.sqlite3-wal"

FORCE_PULL=0
FORCE_PUSH=0
PASSPHRASE=""

# -------------------------------
# Parse command line
# -------------------------------
while getopts "udp:" opt; do
    case "$opt" in
        u) FORCE_PUSH=1 ;;
        d) FORCE_PULL=1 ;;
        p) PASSPHRASE="$OPTARG" ;;
        *)  echo "Usage: $0 [-u|-d] [-p passphrase]"
            exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$PASSPHRASE" ]; then
    echo "ERROR: You must supply a passphrase using -p <passphrase>"
    exit 1
fi

# -------------------------------
# GPG wrappers
# -------------------------------
encrypt_file() {
    src="$1"
    dst="$1.gpg"

    gpg --batch --yes --passphrase "$PASSPHRASE" \
        -o "$dst" -c "$src" || return 1
}

decrypt_file() {
    src="$1"
    out="$(echo "$src" | sed 's/\.gpg$//')"

    gpg --batch --yes --passphrase "$PASSPHRASE" \
        -o "$out" -d "$src" || return 1
}

# -------------------------------
# Rclone wrapper
# -------------------------------
run_rclone() {
    docker run --rm \
        -v "$RCLONE_CONFIG:/config/rclone/rclone.conf" \
        -v "$VW_DATA:$VW_DATA" \
        rclone/rclone:latest "$@"
}

# -------------------------------
# Upload filters
# -------------------------------
run_rclone_upload() {
    run_rclone \
        sync -v \
        --filter="+ *.gpg" \
        --filter="- backups/**" \
        --filter="- **" \
        "$VW_DATA" "$REMOTE_NAME"
}

# -------------------------------
# Download filters
# -------------------------------
run_rclone_download() {
    run_rclone \
        copy -v \
        --filter="+ *.gpg" \
        --filter="- **" \
        "$REMOTE_NAME" "$VW_DATA"
}

# -------------------------------
# Encrypt all local files before upload
# -------------------------------
encrypt_all_local() {
    find "$VW_DATA" -type f ! -name "*.gpg" ! -path "$VW_DATA/backups/*" | while read -r file; do
        encrypt_file "$file" || echo "WARN: Failed to encrypt $file"
    done
}

# -------------------------------
# Decrypt downloaded files
# -------------------------------
decrypt_all_downloaded() {
    find "$VW_DATA" -type f -name "*.gpg" | while read -r file; do
        if decrypt_file "$file"; then
            rm -f "$file"
        else
            echo "ERROR: Failed to decrypt $file"
        fi
    done
}

# -------------------------------
# Backup rotation during pull
# -------------------------------
rotate_local_backup() {
    ts=$(date +"%Y%m%d-%H%M%S")
    mkdir -p "$VW_DATA/backups"
    mv "$VW_DATA/vw-data" "$VW_DATA/backups/vwdata-$ts"
    mkdir -p "$VW_DATA/vw-data"
}

# ==================================================
#             DATABASE DATE LOGIC
# ==================================================

get_local_db_date() {
    [ -f "$DB_FILE" ] && date -r "$DB_FILE" '+%Y-%m-%d' || echo "N/A"
}

get_local_db_days_epoch() {
    [ -f "$DB_FILE" ] && date -d "$(date -r "$DB_FILE" '+%Y-%m-%d')" '+%j' || echo 0
}

local_date=$(get_local_db_date)
local_days_epoch=$(get_local_db_days_epoch)

remote_date_str=$(run_rclone lsl "$REMOTE_NAME" --include "db.sqlite3" | awk '{print $2}')
[ -z "$remote_date_str" ] && remote_date_str="0"

if [ "$remote_date_str" != "0" ]; then
    remote_days_epoch=$(date -d "$remote_date_str" '+%j')
else
    remote_days_epoch=0
fi

diff_days=$(expr "$remote_days_epoch" - "$local_days_epoch" 2>/dev/null || echo 0)

# ==================================================
# Stop container
# ==================================================
docker stop "$VAULTWARDEN_CONTAINER" >/dev/null 2>&1

# ==================================================
# SYNC LOGIC WITH ENCRYPTION
# ==================================================

if [ "$FORCE_PULL" -eq 1 ]; then
    echo "=== FORCE PULL ==="
    rotate_local_backup
    run_rclone_download
    decrypt_all_downloaded

elif [ "$FORCE_PUSH" -eq 1 ]; then
    echo "=== FORCE PUSH ==="
    encrypt_all_local
    run_rclone_upload

elif [ "$remote_date_str" != "0" ] && [ "$diff_days" -gt 1 ]; then
    echo "=== REMOTE NEWER → PULL ==="
    rotate_local_backup
    run_rclone_download
    decrypt_all_downloaded

else
    echo "=== LOCAL NEWER → PUSH ==="
    encrypt_all_local
    run_rclone_upload
fi

# ==================================================
# Restart container
# ==================================================
docker start "$VAULTWARDEN_CONTAINER" >/dev/null 2>&1

echo "Vaultwarden Sync Completed."
exit 0
