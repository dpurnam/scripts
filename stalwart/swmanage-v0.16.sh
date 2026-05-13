#!/bin/bash

# ==========================================================
# Stalwart Full Backup Script (PGDB + Files) - compatible with Stalwart Server >= v0.16.x
# ==========================================================
# This script performs a full backup/restore of Stalwart
# mail server by backing up the PostgreSQL database and
# all files/directories in the Stalwart installation directory.
#
# Backup flow:
#   1. Stop Stalwart container
#   2. Dump, compress & encrypt PostgreSQL database
#   3. Compress & encrypt all other files/directories
#   4. Start rclone container to sync encrypted files to Cloudflare R2
#   5. Start Stalwart container
#   6. Clean up temporary files
#
# Restore flow:
#   1. Pre-backup: backup current state locally (safety net)
#   2. Stop Stalwart container
#   3. Sync encrypted files FROM R2 via rclone
#   4. Rename existing files/dirs → *.old (preservation)
#   5. Decrypt & restore other files/dirs
#   6. Decrypt & restore PostgreSQL database
#   7. Start Stalwart container
#   8. Clean up temporary files
# ==========================================================

set -o pipefail

# --- Global State ---
SCRIPT_DIR=""
SWCONTAINER=""
SWDIR=""
BACKUP_PREFIX=""
BACKUP_DIR_LOCAL=""
BACKUP_DIR_REMOTE=""
RCLONE_REMOTE_NAME=""
PGSQL_DB=""
PGSQL_DB_USER=""
PASSPHRASE=""
MODE=""
KEEP_GZIP_FILES=""
ERROR_OCCURRED=0
RESTORE_ALREADY_DROPPED_DB=0  # flag: 1 = DB was dropped during restore, must be recreated if aborting

# --- Argument Parsing ---
while getopts "p:f:m:k" opt; do
    case ${opt} in
        p ) PASSPHRASE=$OPTARG ;;
        f ) PASSPHRASE_FILE=$OPTARG ;;
        m ) MODE=$OPTARG ;;
        k ) KEEP_GZIP_FILES=true ;;
        \? )
            echo "Usage: $0 -p <passphrase> -f <passphrase_file> -m <backup/restore> -k"
            echo "  -p : (optional) - Passphrase used for GPG file encryption/decryption."
            echo "  -f : (optional) - Path to a file containing the passphrase (more secure than -p)."
            echo "                    If both -p and -f are provided, -p takes precedence."
            echo "  -m : (optional) - Define script mode viz. backup or restore."
            echo "                    If unused, defaults to backup mode."
            echo "  -k : (optional) - If used, keeps the temporary .gzip files for quick local access."
            echo "                    If unused, defaults to deleting the temporary .gzip files"
            exit 1
            ;;
    esac
done

# Resolve passphrase: CLI (-p) > File (-f) > Default file > Error
if [ -z "$PASSPHRASE" ]; then
    if [ -n "$PASSPHRASE_FILE" ]; then
        if [ -f "$PASSPHRASE_FILE" ]; then
            PASSPHRASE=$(head -n 1 "$PASSPHRASE_FILE" | tr -d '\n\r')
            if [ -z "$PASSPHRASE" ]; then
                echo "Error: Passphrase file ($PASSPHRASE_FILE) is empty." >&2
                exit 1
            fi
            echo "INFO: Passphrase loaded from file: $PASSPHRASE_FILE" >&2
        else
            echo "Error: Passphrase file ($PASSPHRASE_FILE) not found." >&2
            exit 1
        fi
    else
        # Try default passphrase file in script directory
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
        DEFAULT_PASS_FILE="$SCRIPT_DIR/swmanage-passphrase.conf"
        if [ -f "$DEFAULT_PASS_FILE" ]; then
            PASSPHRASE=$(head -n 1 "$DEFAULT_PASS_FILE" | tr -d '\n\r')
            if [ -z "$PASSPHRASE" ]; then
                echo "Error: Default passphrase file ($DEFAULT_PASS_FILE) is empty." >&2
                exit 1
            fi
            echo "INFO: Passphrase loaded from default file: $DEFAULT_PASS_FILE" >&2
        else
            echo "Error: No passphrase provided." >&2
            echo "       Use -p <passphrase> or -f <passphrase_file>." >&2
            echo "       Or create a passphrase file at: $DEFAULT_PASS_FILE" >&2
            exit 1
        fi
    fi
fi

# Resolve script directory (may not have been set if passphrase came from -p)
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
fi

# Default to backup if no mode argument provided
if [ -z "$MODE" ]; then
    echo "(-m) option not provided. Defaulting to backup Mode." && echo ""
    MODE="backup"
fi

### --- Script Configuration ---
# Define the configuration file paths relative to the script's directory
MAIN_CONFIG_FILE="$SCRIPT_DIR/swmanage-config.conf"
RCLONE_CONFIG_FILE="$SCRIPT_DIR/swmanage-rclone.conf"
RAW_GITHUB_URL_RCLONE_CONF="https://raw.githubusercontent.com/dpurnam/scripts/main/stalwart/swmanage-rclone.conf"
RAW_GITHUB_URL_MAIN_CONF="https://raw.githubusercontent.com/dpurnam/scripts/main/stalwart/swmanage-config.conf"

# Rclone configuration file availability with error handling
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
    echo "WARN: The Rclone configuration file ($RCLONE_CONFIG_FILE) is missing, locally!" >&2
    echo "INFO: Downloading Sample Rclone configuration file to ($RCLONE_CONFIG_FILE) from Github ($RAW_GITHUB_URL_RCLONE_CONF)..." >&2
    if ! wget -q -O "$RCLONE_CONFIG_FILE" "$RAW_GITHUB_URL_RCLONE_CONF"; then
        echo "ERROR: Failed to download the Rclone configuration file. Please check your internet connection or the URL or download it manually." >&2
        echo "Exiting." >&2 && echo ""
        exit 1
    fi
    echo "INFO: Sample Rclone configuration file successfully downloaded." >&2
    echo "NOTICE: Modify the downloaded Rclone configuration file ($RCLONE_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    echo "Exiting." >&2 && echo ""
    exit 1
fi

# Main configuration file availability with error handling
if [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo "WARN: The Main configuration file ($MAIN_CONFIG_FILE) is missing, locally!" >&2
    echo "INFO: Downloading Sample Main configuration file to ($MAIN_CONFIG_FILE) from Github ($RAW_GITHUB_URL_MAIN_CONF)..." >&2
    if ! wget -q -O "$MAIN_CONFIG_FILE" "$RAW_GITHUB_URL_MAIN_CONF"; then
        echo "ERROR: Failed to download the Main configuration file. Please check your internet connection or the URL or download it manually." >&2
        echo "Exiting." >&2 && echo ""
        exit 1
    fi
    echo "INFO: Sample Main configuration file successfully downloaded." >&2
    echo "NOTICE: Modify the downloaded Main configuration file ($MAIN_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    echo "Exiting." >&2 && echo ""
    exit 1
fi

# Source the Main Config File
# shellcheck source=/dev/null
source "$MAIN_CONFIG_FILE"

### --- Error Handling & Cleanup Trap ---
# Cleanup function: ensures nothing destructive is left pending on exit/error
cleanup_on_exit() {
    # If we were in a restore and the DB was dropped but not recreated, flag it
    if [ "$RESTORE_ALREADY_DROPPED_DB" -eq 1 ] && [ "$ERROR_OCCURRED" -eq 1 ]; then
        echo "" >&2
        echo "!!! CRITICAL: Database '$PGSQL_DB' was dropped during a failed restore !!!" >&2
        echo "!!! The safety backup .gpg files exist locally. Manually restore them.   !!!" >&2
    fi

    if [ "$ERROR_OCCURRED" -eq 1 ]; then
        echo "" >&2
        echo "!!! ERROR DETECTED — Initiating safe cleanup !!!" >&2
        echo "INFO: Ensuring Stalwart container is running..." >&2
        # Try to start the container, silence errors since we're already in cleanup
        if docker_start 2>/dev/null; then
            echo "INFO: Stalwart container is running." >&2
        fi
        echo "INFO: Cleanup complete. Production stack is restored as safely as possible." >&2
        echo "!!! Check logs above for the failure details. !!!" >&2
    fi
}
trap cleanup_on_exit EXIT

# mark_error: mark a non-fatal error and let the script continue if possible,
# but the final EXIT trap will handle safeguarding the production stack.
# Returns 1 so callers can use: mark_error "msg" || return 1
mark_error() {
    ERROR_OCCURRED=1
    echo "ERROR: $1" >&2
    return 1
}

### --- Functions ---

## --- Stalwart Docker Functions ---
docker_start() {
    if ! docker ps -q --filter "name=$SWCONTAINER" | grep -q .; then
        echo "Starting Docker Container: $SWCONTAINER ..."
        if ! docker start "$SWCONTAINER" > /dev/null 2>&1; then
            echo "ERROR: Failed to start Docker container: $SWCONTAINER" >&2
            return 1
        fi
        sleep 5
        echo "Started Docker Container: $SWCONTAINER !" && echo ""
    fi
}

docker_stop() {
    if docker ps -q --filter "name=$SWCONTAINER" | grep -q .; then
        echo "Stopping Docker Container: $SWCONTAINER ..."
        if ! docker stop "$SWCONTAINER" > /dev/null 2>&1; then
            echo "ERROR: Failed to stop Docker container: $SWCONTAINER" >&2
            return 1
        fi
        sleep 5
        echo "Stopped Docker Container: $SWCONTAINER !" && echo ""
    fi
}

## --- Rclone Docker Function ---
run_rclone() {
    local rclone_output
    rclone_output=$(docker run --rm \
        -v "$RCLONE_CONFIG_FILE:/config/rclone/rclone.conf" \
        -v "$SWDIR:$SWDIR" \
        rclone/rclone:latest "$@" 2>&1)
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "ERROR: rclone command failed: '$*' (Exit code: $status)" >&2
        echo "Rclone output: $rclone_output" >&2
        return 1
    fi
    echo "$rclone_output"
    return 0
}

## --- Basic GPG Functions ---
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    rm -f "$output_file"
    if ! echo -n "$passphrase" | gpg --batch --passphrase-fd 0 --symmetric \
         --pinentry-mode loopback --output "$output_file" "$input_file" 2>&1; then
        echo "ERROR: GPG encryption failed for: $input_file" >&2
        return 1
    fi
    # Verify output file was created and is non-empty
    if [ ! -s "$output_file" ]; then
        echo "ERROR: GPG encryption produced empty or missing output: $output_file" >&2
        return 1
    fi
    return 0
}

decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    rm -f "$output_file"
    if ! echo -n "$passphrase" | gpg --batch --passphrase-fd 0 --decrypt \
         --output "$output_file" "$input_file" 2>&1; then
        echo "ERROR: GPG decryption failed for: $input_file (wrong passphrase or corrupted file?)" >&2
        return 1
    fi
    # Verify output file was created and is non-empty
    if [ ! -s "$output_file" ]; then
        echo "ERROR: GPG decryption produced empty or missing output: $output_file" >&2
        return 1
    fi
    return 0
}

## --- PostgresSQL DB Functions ---
database_exists() {
    local output
    output=$(sudo -u postgres psql -Atqc "SELECT 1 FROM pg_database WHERE datname='$PGSQL_DB';" 2>/dev/null)
    if [ "$output" = "1" ]; then
        return 0 # Database exists
    else
        return 1 # Database does not exist or error
    fi
}

drop_database() {
    echo "Attempting to drop database: $PGSQL_DB"
    if ! cd /tmp || ! sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$PGSQL_DB\" WITH (FORCE);" 2>&1; then
        echo "ERROR: Failed to drop database: $PGSQL_DB" >&2
        echo "       Please check PostgreSQL logs or manually delete, create and import the database." >&2
        return 1
    fi
    echo "Database '$PGSQL_DB' dropped successfully (if it existed)." && echo ""
}

create_database() {
    if ! cd /tmp || ! sudo -u postgres psql \
         -c "CREATE DATABASE \"$PGSQL_DB\" OWNER \"$PGSQL_DB_USER\";" 2>&1; then
        echo "ERROR: Failed to create database: $PGSQL_DB" >&2
        echo "       Please check PostgreSQL logs or manually create and import the database." >&2
        return 1
    fi
    echo "Database '$PGSQL_DB' created with owner '$PGSQL_DB_USER'." && echo ""
}

pgsqldb_backup_compress_encrypt() {
    local pgsql_file=$PGSQL_DB.pgsql
    local gzip_file="$pgsql_file.gzip"
    local gpg_file="$BACKUP_DIR_LOCAL/db/$gzip_file.gpg"

    echo "=========>> Exporting, Compressing & Encrypting PostgreSQL DB ($PGSQL_DB) ... =========>>" && echo ""
    start_time=$SECONDS

    mkdir -p "$BACKUP_DIR_LOCAL/db"

    # Dump + compress
    if ! cd /tmp || ! sudo -H -u postgres pg_dump -d "$PGSQL_DB" --blobs --verbose -Fc 2>&1 | gzip > "/tmp/$gzip_file"; then
        echo "ERROR: pg_dump or gzip failed for database: $PGSQL_DB" >&2
        rm -f "/tmp/$gzip_file"
        return 1
    fi

    # Verify dump produced data
    if [ ! -s "/tmp/$gzip_file" ]; then
        echo "ERROR: pg_dump produced empty output for database: $PGSQL_DB" >&2
        rm -f "/tmp/$gzip_file"
        return 1
    fi

    # Encrypt
    if ! encrypt_file "/tmp/$gzip_file" "$gpg_file" "$PASSPHRASE"; then
        rm -f "/tmp/$gzip_file"
        return 1
    fi

    # Preserve local gzip if -k flag is used
    if [ -n "$KEEP_GZIP_FILES" ]; then
        mv "/tmp/$gzip_file" "$BACKUP_DIR_LOCAL/db/"
    else
        rm -f "/tmp/$gzip_file"
    fi

    echo "<<========= PostgreSQL DB ($PGSQL_DB) Exported, Compressed and Encrypted! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

pgsqldb_decrypt_decompress_restore() {
    local pgsql_file=$PGSQL_DB.pgsql
    local gzip_file="$pgsql_file.gzip"
    local gpg_file="$BACKUP_DIR_REMOTE/db/$gzip_file.gpg"

    echo "=========>> Decrypting, Decompressing & Restoring PostgreSQL DB ($PGSQL_DB) ... =========>>" && echo ""
    start_time=$SECONDS

    if [ ! -f "$gpg_file" ]; then
        echo "ERROR: Encrypted database backup not found at $gpg_file" >&2
        return 1
    fi

    # --- CRITICAL SECTION: database will be dropped ---
    # If DB exists, drop it.  If this fails, abort before any data is lost.
    if database_exists; then
        if ! drop_database; then
            return 1
        fi
        RESTORE_ALREADY_DROPPED_DB=1    # flag for EXIT trap
    fi

    # Decrypt
    if ! decrypt_file "$gpg_file" "/tmp/$gzip_file" "$PASSPHRASE"; then
        # DB is already dropped but decryption failed – critical situation
        echo "CRITICAL: Database '$PGSQL_DB' was dropped but decryption of backup failed." >&2
        echo "          The backup file may be corrupted or passphrase is wrong." >&2
        echo "          A safety backup exists locally (restore pre-backup)." >&2
        return 1
    fi

    # Create fresh database
    if ! create_database; then
        rm -f "/tmp/$gzip_file"
        return 1
    fi

    # Decompress to plain pg_dump custom-format file
    if ! gunzip -c "/tmp/$gzip_file" > "/tmp/$pgsql_file"; then
        echo "ERROR: gunzip decompression failed for: /tmp/$gzip_file" >&2
        rm -f "/tmp/$gzip_file"
        return 1
    fi
    # Clean up gzip now that we have the decompressed file
    rm -f "/tmp/$gzip_file"

    # Restore from decompressed file (avoids stdin pipe issues with sudo)
    if ! cd /tmp || ! sudo -u postgres pg_restore -d "$PGSQL_DB" --verbose "/tmp/$pgsql_file" 2>&1; then
        echo "ERROR: pg_restore failed for database: $PGSQL_DB. The old database was dropped." >&2
        echo "       A safety backup exists locally at $BACKUP_DIR_LOCAL" >&2
        rm -f "/tmp/$pgsql_file"
        return 1
    fi

    # All good – reset the flag since DB is now recreated
    RESTORE_ALREADY_DROPPED_DB=0
    rm -f "/tmp/$pgsql_file"
    echo "<<========= PostgreSQL DB ($PGSQL_DB) Decrypted, Decompressed and Restored! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

## --- Functions for other directories/files ---
compress_encrypt_others() {
    echo ""
    echo "=========>> Compressing and encrypting other top level directories & files for upload... <<=========" && echo ""
    start_time=$SECONDS

    # Top Level Directories in SWDIR (exclude SWDIR itself and the backup directory)
    local dir_result=0
    local file_result=0

    while read -r dir; do
        local dir_name
        dir_name=$(basename "$dir")
        local gzip_file="$BACKUP_DIR_LOCAL/tld_$dir_name.gzip"
        local gpg_file="$gzip_file.gpg"

        echo "Compressing Directory: $dir_name ..."
        if ! tar -czf "$gzip_file" -C "$SWDIR" "$dir_name"; then
            echo "ERROR: tar compression failed for directory: $dir_name" >&2
            rm -f "$gzip_file"
            dir_result=1
            continue
        fi

        echo "Encrypting Directory: $dir_name ..." && echo ""
        if ! encrypt_file "$gzip_file" "$gpg_file" "$PASSPHRASE"; then
            rm -f "$gzip_file"
            dir_result=1
            continue
        fi

        if [ -z "$KEEP_GZIP_FILES" ]; then
            rm -f "$gzip_file"
        fi
    done < <(find "$SWDIR" -maxdepth 1 -type d ! -path "$SWDIR" ! -path "$SWDIR/$BACKUP_PREFIX")

    # Top Level Files in SWDIR
    while read -r file; do
        local file_name
        file_name=$(basename "$file")
        local gzip_file="$BACKUP_DIR_LOCAL/tlf_$file_name.gzip"
        local gpg_file="$gzip_file.gpg"

        echo "Compressing File: $file_name ..."
        if ! gzip -c "$file" > "$gzip_file"; then
            echo "ERROR: gzip compression failed for file: $file_name" >&2
            rm -f "$gzip_file"
            file_result=1
            continue
        fi

        echo "Encrypting File: $file_name ..." && echo ""
        if ! encrypt_file "$gzip_file" "$gpg_file" "$PASSPHRASE"; then
            rm -f "$gzip_file"
            file_result=1
            continue
        fi

        if [ -z "$KEEP_GZIP_FILES" ]; then
            rm -f "$gzip_file"
        fi
    done < <(find "$SWDIR" -maxdepth 1 -type f)

    if [ "$dir_result" -ne 0 ] || [ "$file_result" -ne 0 ]; then
        echo "WARNING: Some directories or files failed to compress/encrypt. See errors above." >&2
        return 1
    fi

    echo "<<========= Compression and encryption of other top level directories & files completed! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

decrypt_decompress_others() {
    echo ""
    echo "=========>> Decrypting and decompressing the downloaded other top level directories & files... <<=========" && echo ""
    echo "INFO: Existing files/directories will be moved to *.old as a fallback." && echo ""
    start_time=$SECONDS

    # 1. Rename existing top-level directories to *.old (excluding backup dir)
    while read -r dir; do
        local dir_name_local
        dir_name_local=$(basename "$dir")
        # Only rename if a corresponding backup exists (to avoid cluttering with unrelated *.old)
        if ls "$BACKUP_DIR_REMOTE/tld_${dir_name_local}.gzip.gpg" > /dev/null 2>&1; then
            if [ -d "$SWDIR/$dir_name_local" ] && [ ! -d "$SWDIR/$dir_name_local.old" ]; then
                echo "Preserving existing directory '$dir_name_local' as '$dir_name_local.old'..."
                mv "$SWDIR/$dir_name_local" "$SWDIR/$dir_name_local.old"
            fi
        fi
    done < <(find "$SWDIR" -maxdepth 1 -type d ! -path "$SWDIR" ! -path "$SWDIR/$BACKUP_PREFIX")

    # 2. Rename existing top-level files to *.old
    while read -r file; do
        local file_name
        file_name=$(basename "$file")
        # Only rename if a corresponding backup exists
        if ls "$BACKUP_DIR_REMOTE/tlf_${file_name}.gzip.gpg" > /dev/null 2>&1; then
            if [ -f "$SWDIR/$file_name" ] && [ ! -f "$SWDIR/$file_name.old" ]; then
                echo "Preserving existing file '$file_name' as '$file_name.old'..."
                mv "$SWDIR/$file_name" "$SWDIR/$file_name.old"
            fi
        fi
    done < <(find "$SWDIR" -maxdepth 1 -type f)

    # 3. Decrypt and extract each backup file
    while read -r gpg_file; do
        local base_name
        base_name=$(basename "$gpg_file")
        local gzip_file="$BACKUP_DIR_REMOTE/${base_name%.gpg}"

        echo "Decrypting $base_name..."
        if ! decrypt_file "$gpg_file" "$gzip_file" "$PASSPHRASE"; then
            echo "WARNING: Failed to decrypt $base_name. Skipping this file. Original data preserved as *.old." >&2
            rm -f "$gzip_file"
            continue
        fi

        local original_name="${base_name%.gzip.gpg}"

        if [[ "$original_name" == tld_* ]]; then
            local dir_name="${original_name#tld_}"
            echo "Extracting directory backup of '$dir_name'..."
            if ! tar -xzf "$gzip_file" -C "$SWDIR"; then
                echo "ERROR: tar extraction failed for directory backup: $dir_name" >&2
                echo "       Original data is preserved as $SWDIR/$dir_name.old" >&2
                rm -f "$gzip_file"
                return 1
            fi
        elif [[ "$original_name" == tlf_* ]]; then
            local file_name="${original_name#tlf_}"
            echo "Extracting file backup of '$file_name'..."
            if ! gunzip -c "$gzip_file" > "$SWDIR/$file_name"; then
                echo "ERROR: gunzip extraction failed for file backup: $file_name" >&2
                echo "       Original data is preserved as $SWDIR/$file_name.old" >&2
                rm -f "$gzip_file"
                return 1
            fi
        else
            echo "Warning: Unrecognized file prefix for '$original_name'. Skipping extraction."
        fi

        if [ -z "$KEEP_GZIP_FILES" ]; then
            rm -f "$gzip_file"
        fi
    done < <(find "$BACKUP_DIR_REMOTE" -maxdepth 1 -type f -name "*.gzip.gpg")

    echo "<<========= Decryption and decompression of other top level directories & files completed! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

# --- Main Script ---
SECONDS=0 # Start the master timer

if [[ ! "$MODE" == "restore" ]]; then
    # =============================================
    #              BACKUP MODE
    # =============================================
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>"
    echo "===>      Initiating Stalwart Mail Server Backup.      ===>"
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>" && echo ""

    ## Step 1: Stop Stalwart Container for consistent backup
    if ! docker_stop; then
        mark_error "Failed to stop Stalwart container during backup"
    fi
    sleep 3

    ## Step 2: PostgreSQL Database Backup
    if ! pgsqldb_backup_compress_encrypt; then
        mark_error "PostgreSQL backup failed"
    fi
    sleep 3

    ## Step 3: Backup other files & directories
    if ! compress_encrypt_others; then
        mark_error "File/directory backup failed"
    fi
    sleep 3

    ## Step 4: Start Stalwart Container (restore service)
    if ! docker_start; then
        mark_error "Failed to restart Stalwart container after backup"
    fi
    sleep 3

    ## Step 5: Rclone Sync encrypted files to R2
    echo "=========>> Initiating Rclone Sync: $SWSERVER --> R2... =========>>" && echo ""
    start_time=$SECONDS
    if ! run_rclone sync -v --filter "+ *.gzip.gpg" --filter "- *" "$BACKUP_DIR_LOCAL" "$RCLONE_REMOTE_NAME"; then
        mark_error "Rclone sync to R2 failed. Encrypted backup files are still available locally at $BACKUP_DIR_LOCAL"
    fi
    sleep 3
    echo "<<========= Rclone Sync to R2 Completed: $SWSERVER --> R2. (in $((SECONDS - start_time)) seconds)<<=========" && echo ""

    ## Step 6: Final cleanup
    echo "=========>> Cleaning up... =========>>"
    # Delete GZIP files only if -k flag was NOT used (encrypted .gpg files are always kept locally)
    if [ -z "$KEEP_GZIP_FILES" ]; then
        find "$BACKUP_DIR_LOCAL" -name "*.gzip" -delete
    fi
    echo "<<========= Cleanup Completed. <<=========" && echo ""

    if [ "$ERROR_OCCURRED" -eq 1 ]; then
        echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <==="
        echo "<===      Stalwart Mail Server Backup Completed WITH WARNINGS.     ===>"
        echo "<===      Check error messages above. Encrypted local backup exists. ===>"
        echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <===" && echo ""
    else
        echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <==="
        echo "<===      Stalwart Mail Server Backup Completed Successfully!     <=== (in $SECONDS seconds)"
        echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <===" && echo ""
    fi
    exit 0

else
    # =============================================
    #              RESTORE MODE
    # =============================================
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>"
    echo "===>      Initiating Stalwart Mail Server Restore.     ===>"
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>" && echo ""

    ## Step 0: Pre-backup current state (safety net) before restoring
    echo "--- Step 0: Creating a local safety backup of the current state... ---" && echo ""
    if ! docker_stop; then
        mark_error "Failed to stop Stalwart container during restore pre-backup"
    fi
    sleep 3
    if ! pgsqldb_backup_compress_encrypt; then
        mark_error "Pre-restore safety backup of PostgreSQL failed. Aborting restore."
    fi
    sleep 3
    if ! compress_encrypt_others; then
        mark_error "Pre-restore safety backup of files failed. Aborting restore."
    fi
    sleep 3
    echo "--- Safety backup completed. ---" && echo ""

    ## Step 1: Rclone Sync encrypted files FROM R2
    echo "=========>> Initiating Rclone Sync: $SWSERVER <-- R2... =========>>" && echo ""
    start_time=$SECONDS
    if ! run_rclone sync -v --filter "+ *.gzip.gpg" --filter "- *" "$RCLONE_REMOTE_NAME" "$BACKUP_DIR_REMOTE"; then
        mark_error "Rclone sync from R2 failed. Cannot proceed with restore."
        echo "WARNING: Your local safety backup is still intact. You can restore from it manually." >&2
    fi
    sleep 3
    echo "<<========= Rclone Sync Completed: $SWSERVER <-- R2. (in $((SECONDS - start_time)) seconds)<<=========" && echo ""

    ## Step 2: Decrypt & Decompress other top level folders (preserving existing as *.old)
    if ! decrypt_decompress_others; then
        mark_error "Decryption/decompression of files failed during restore"
    fi
    sleep 3

    ## Step 3: Restore PostgreSQL Database
    if ! pgsqldb_decrypt_decompress_restore; then
        mark_error "PostgreSQL database restore failed"
    fi
    sleep 3

    ## Step 4: Start Stalwart Container
    if ! docker_start; then
        mark_error "Failed to start Stalwart container after restore"
    fi
    sleep 3

    # Step 5: Final cleanup
    find "$SWDIR" -name "*.sh" -exec sudo chmod +x {} +
    

    echo "=========>> Cleaning up... =========>>"
    if [ -z "$KEEP_GZIP_FILES" ]; then
        find "$BACKUP_DIR_REMOTE" -name "*.gzip" -delete
    fi
    echo "<<========= Cleanup Completed. <<=========" && echo ""

    if [ "$ERROR_OCCURRED" -eq 1 ]; then
        echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <==="
        echo "<===      Stalwart Mail Server Restore Completed WITH WARNINGS.     ===>"
        echo "<===      Check error messages above.                              ===>"
        echo "<===      Safety backup exists locally at $BACKUP_DIR_LOCAL          ===>"
        echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <==="
        echo ""
        echo "!!! If everything works correctly, remove *.old files: !!!"
        echo "!!!   sudo find "$SWDIR" -name "*.old" -print -exec sudo rm -R -f {} +      !!!"
        echo "=== === ^^^ Goodbye! ^^^ === ===" && echo ""
    else
        echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <==="
        echo "<===      Stalwart Mail Server Restore Completed Successfully!     <=== (in $SECONDS seconds)"
        echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <===" && echo ""
        echo "!!! If everything works correctly, remove *.old files: !!!"
        echo "!!!   sudo find "$SWDIR" -name "*.old" -print -exec sudo rm -R -f {} +      !!!"
        echo "=== === ^^^ Goodbye! ^^^ === ===" && echo ""
    fi
    exit 0
fi
