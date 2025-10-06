#!/bin/bash

# ==========================================================
# Stalwart Full Backup Script (Accounts & PGSQL DB )
# ==========================================================

# --- Argument Parsing ---
# Initialize variables to hold argument values
SWPASSWORD=""
PASSPHRASE=""
MODE=""
KEEP_GZIP_FILES=""
CUSTOM_ACCOUNTS=""

# Parse command-line flags for Stalwart password (-c) and passphrase (-p)
while getopts "c:p:m:kz" opt; do
    case ${opt} in
        c ) SWPASSWORD=$OPTARG ;;
        p ) PASSPHRASE=$OPTARG ;;
        m ) MODE=$OPTARG ;;
        k ) KEEP_GZIP_FILES=true ;;
        z ) CUSTOM_ACCOUNTS=true ;;
        \? )
            echo "Usage: $0 -c <stalwart_admin_password> -p <passphrase> -m <backup/restore> -k -z"
            echo "  -m : (optional) - Define script mode viz. backup or restore."
            echo "                    If unused, defaults to backup mode." && echo ""
            echo "  -k : (optional) - If used, keeps the temporary .gzip file for quick local access."
            echo "                    If unused, defaults to deleting the temporary .gzip files after the script completes" && echo ""
            echo "  -z : (optional) - If used, allows to work on custom list of DOMAINS/ACCOUNTS (info must be provied in the Main config file!)"
            echo "                    If unused, defaults to working on ALL Individual ACCOUNTS from the server." && echo ""
            exit 1
            ;;
    esac
done

# Check if required arguments were provided
if [ -z "$SWPASSWORD" ] || [ -z "$PASSPHRASE" ]; then
    echo "Error: At least the Stalwart Admin password (-c) and your file encryption passphrase (-p) are required."
    echo "Usage: $0 -c <stalwart_admin_password> -p <passphrase> -o <backup/restore> -k -z"
    echo "  -m : (optional) - Define script mode viz. backup or restore."
    echo "                    If unused, defaults to backup mode." && echo ""
    echo "  -k : (optional) - If used, keeps the temporary .gzip file for quick local access."
    echo "                    If unused, defaults to deleting the temporary .gzip files after the script completes" && echo ""
    echo "  -z : (optional) - If used, allows to work on custom list of DOMAINS/ACCOUNTS (info must be provied in the Main config file!)"
    echo "                    If unused, defaults to working on ALL Individual ACCOUNTS from the server." && echo ""
    exit 1
fi

# Default to backup, if no argument provided for (-o)
if [ ! -z "$MODE" ]; then
    echo "(-m) option not provided. Defaulting to backup Mode" && echo ""
    MODE="backup"
fi

### --- Script Configuration ---
# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Define the configuration file paths relative to the script's directory
MAIN_CONFIG_FILE="$SCRIPT_DIR/swmanage-config.conf"
RCLONE_CONFIG_FILE="$SCRIPT_DIR/swmanage-rclone.conf"
RAW_GITHUB_URL_RCLONE_CONF="https://raw.githubusercontent.com/dpurnam/scripts/main/stalwart/swmanage-rclone.conf"
RAW_GITHUB_URL_MAIN_CONF="https://raw.githubusercontent.com/dpurnam/scripts/main/stalwart/swmanage-config.conf"

# Rclone configuration file availability with error handling
if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
    echo "WARN: The Rclone configuration file ($RCLONE_CONFIG_FILE) is missing, locally!" >&2
    echo "INFO: Downloading Sample Rclone configuration file to ($RCLONE_CONFIG_FILE) from Github ($RAW_GITHUB_URL_RCLONE_CONF)..." >&2
    wget -q -O "$RCLONE_CONFIG_FILE" "$RAW_GITHUB_URL_RCLONE_CONF"
    # Check if the download was successful
    if [ $? -eq 0 ]; then
        echo "INFO: Sample Rclone configuration file successfully downloaded." >&2
        echo "NOTICE: Modify the downloaded Rclone configuration file ($RCLONE_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    else
        echo "ERROR: Failed to download the Rclone configuration file. Please check your internet connection or the URL or download it manually in the $SWDIR directory." >&2
        echo "NOTICE: Modify the downloaded Rclone configuration file ($RCLONE_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    fi
    echo "Exiting." >&2 && echo ""
    exit 1
fi
# Main configuration file availability with error handling
if [ ! -f "$MAIN_CONFIG_FILE" ]; then
    echo "WARN: The Main configuration file ($MAIN_CONFIG_FILE) is missing, locally!" >&2
    echo "INFO: Downloading Sample Main configuration file to ($MAIN_CONFIG_FILE) from Github ($RAW_GITHUB_URL_MAIN_CONF)..." >&2
    wget -q -O "$MAIN_CONFIG_FILE" "$RAW_GITHUB_URL_MAIN_CONF"
    # Check if the download was successful
    if [ $? -eq 0 ]; then
        echo "INFO: Sample Main configuration file successfully downloaded." >&2
        echo "NOTICE: Modify the downloaded Main configuration file ($MAIN_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    else
        echo "ERROR: Failed to download the Main configuration file. Please check your internet connection or the URL or download it manually in the $SWDIR directory." >&2
        echo "NOTICE: Modify the downloaded Main configuration file ($MAIN_CONFIG_FILE) according to your environment and re-run the main script." >&2 && echo ""
    fi
    echo "Exiting." >&2 && echo ""
    exit 1
else
    # source the Main Config FIle
    source $MAIN_CONFIG_FILE
fi
# Redundent code block to be removed later
#else
#    echo "Loading configuration from $CONFIG_FILE" && echo ""
#    # Capture Main Script variables from semicolon comments of the CONFIG_FILE in between MAIN_SCRIPT_VARS_START & MAIN_SCRIPT_VARS_END
#    # s/^;//p - captures only variables that have no space between the semicolon and the variable itself
#    swmanage_config_vars=$(sed -n '/^;======>MAIN_SCRIPT_VARS_START/,/^;<======MAIN_SCRIPT_VARS_END/ {
#    /^;======>MAIN_SCRIPT_VARS_START/b
#    /^;<======MAIN_SCRIPT_VARS_END/b
#    s/^;//p
#    }' "$CONFIG_FILE")
#    # Print the variables that were captured
#    echo "--- Parsed Variables from $CONFIG_FILE ---" && echo ""
#    echo "$swmanage_config_vars"
#    echo "-------------------------------------------" && echo ""
#    # Load the variables from the captured output
#    eval "$swmanage_config_vars"
#fi
# Redundent code block to be removed later

### --- Generate ACCOUNTS Array ---
ACCOUNTS=()
if [ -z "$CUSTOM_ACCOUNTS" ]; then
    if ! command -v jq &> /dev/null; then
        apt install jq -y > /dev/null 2>&1
    fi
    # Fetch accounts from the server and store the JSON output
    if ! ACCOUNTS_JSON=$(curl -sSL -u "admin:$SWPASSWORD" "$SWURL/api/principal"); then
        echo "ERROR: Failed to connect to Stalwart server at $SWURL. Please check your network connection and credentials." >&2
        exit 1
    fi
    # Check for empty or invalid JSON response before parsing
    if [ -z "$ACCOUNTS_JSON" ] || ! echo "$ACCOUNTS_JSON" | jq -e '.data.items[] | select(.type == "individual")' > /dev/null 2>&1; then
        echo "ERROR: No individual accounts found or invalid response from the server." >&2
        echo "NOTICE: Please ensure there are accounts to manage or manually populate the ACCOUNTS array in your config file." >&2
        exit 1
    fi
    # Use a here-string to safely populate the array from the JSON output
    while read -r account; do
        ACCOUNTS+=("$account")
    done <<< "$(echo "$ACCOUNTS_JSON" | jq -r '.data.items[] | select(.type == "individual").name')"
    
    # Final check after array population
    if [ ${#ACCOUNTS[@]} -eq 0 ]; then
        echo "ERROR: Failed to populate ACCOUNTS array from server data." >&2
        echo "NOTICE: Manually populate the config file with relevant info about Domains/Accounts and re-run the script with (-z) option." >&2 && echo ""
        exit 1
    fi
    
    echo "SUCCESS: Found ${#ACCOUNTS[@]} individual accounts."
    printf "%s\n" "${ACCOUNTS[@]}"
    echo ""
else
    echo "INFO: (-z) option used. Generating Account List based on Main Config file." && echo ""
    sleep 1
    # Populate ACCOUNTS with DOMAINS in their Names
    for entry in "${ACCOUNTS_WITH_DOMAINS[@]}"; do
        read -ra parts <<< "$entry"
        if [[ ${#parts[@]} -gt 0 ]]; then
            domain="${parts[0]}"
            unset 'parts[0]'
            for user in "${parts[@]}"; do
                ACCOUNTS+=("$user@$domain")
            done
        fi
    done
    # Populate ACCOUNTS without DOMAINS in their Names
    for user in "${ACCOUNTS_WITHOUT_DOMAINS[@]}"; do
        ACCOUNTS+=("$user")
    done
    printf "%s\n" "${ACCOUNTS[@]}"
    echo ""
fi

### --- Functions ---
## --- Stalwart Docker Functions ---
docker_start() {
    if ! docker ps -q --filter "name=$SWCONTAINER" | grep -q .; then
        echo "Starting docker Container: $SWCONTAINER ..."
        docker start "$SWCONTAINER" > /dev/null 2>&1 && sleep 5
        echo "Started docker Container: $SWCONTAINER !" && echo ""
    fi
}
docker_stop() {
    if docker ps -q --filter "name=$SWCONTAINER" | grep -q .; then
        echo "Stopping docker container:  $SWCONTAINER ..."
        docker stop "$SWCONTAINER" > /dev/null 2>&1 && sleep 5
        echo "Stopped docker Container: $SWCONTAINER !" && echo ""
    fi
}

## --- Rclone Docker Function ---
run_rclone() {
    docker run --rm \
        -v "$RCLONE_CONFIG_FILE:/config/rclone/rclone.conf" \
        -v "$SWDIR:$SWDIR" \
        rclone/rclone:latest "$@"
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "Error running rclone command: '$*' (Exit code: $status)" >&2
        return 1
    fi
    return 0
}

## --- Basic GPG Functions ---
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    rm -f "$output_file"
    echo -n "$passphrase" | gpg --batch --passphrase-fd 0 --symmetric --pinentry-mode loopback --output "$output_file" "$input_file"
}
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    rm -f "$output_file"
    echo -n "$passphrase" | gpg --batch --passphrase-fd 0 --decrypt  --output "$output_file" "$input_file"
}

## --- Stalwart Email Account Functions ---
export_account() {
    local account="$1"
    local account_dir="$BACKUP_DIR_LOCAL/accounts/$account"
    local gzip_file="$account_dir.gzip"
    local gpg_file="$gzip_file.gpg"

    echo "===> Exporting account: $account..."
    mkdir -p "$account_dir"
    docker exec -t "$SWCONTAINER" bash -c 'stalwart-cli -c "$1" -u "$2" export account "$3" "$4"' _ "$SWPASSWORD" "$SWURL" "$account" "$BACKUP_PREFIX/$SWSERVER-local/accounts/$account"
    tar -czf "$gzip_file" -C "$BACKUP_DIR_LOCAL/accounts" "$account" > /dev/null 2>&1
    encrypt_file "$gzip_file" "$gpg_file" "$PASSPHRASE"
    rm -rf "$account_dir"
    echo "<=== Exported account: $account" && echo ""
}
import_account() {
    local account="$1"
    local account_dir="$BACKUP_DIR_REMOTE/accounts/$account"
    local gzip_file="$account_dir.gzip"
    local gpg_file="$gzip_file.gpg"

    echo "===> Importing account: $account from $account_dir..."
    decrypt_file "$gpg_file" "$gzip_file" "$PASSPHRASE"
    tar -xzf "$gzip_file" -C "$BACKUP_DIR_REMOTE/accounts" >/dev/null 2>&1
    docker exec -t "$SWCONTAINER" bash -c 'stalwart-cli -c "$1" -u "$2" import account "$3" "$4"' _ "$SWPASSWORD" "$SWURL" "$account" "$BACKUP_PREFIX/$SWSERVER-remote/accounts/$account"
    echo "<=== Imported account: $account from $account_dir..." && echo ""
}

## --- PostgresSQL DB Functions ---
database_exists() {
    local output=$(sudo -u postgres psql -Atqc "SELECT 1 FROM pg_database WHERE datname='$PGSQL_DB';")
    if [ "$output" -eq "1" ]; then
        return 0 # Database exists
    else
        return 1 # Database does not exist or error
    fi
}
drop_database() {
    echo "Attempting to drop database: $PGSQL_DB"
    cd /tmp && sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$PGSQL_DB\" WITH (FORCE);" 2>&1
    if [ "$?" -eq 0 ]; then
        echo "Database '$PGSQL_DB' dropped successfully (if it existed)." && echo ""
    else
        echo "Error dropping database '$PGSQL_DB'. Please check PostgresSQL logs or manually delete, create and import the database.." && echo ""
        exit 1
    fi
}
create_database() {
    # Create the database and assign an owner
    cd /tmp && sudo -u postgres psql -c "CREATE DATABASE \"$PGSQL_DB\" OWNER \"$PGSQL_DB_USER\";" 2>&1
    if [ "$?" -eq 0 ]; then
        echo "Database '$PGSQL_DB' created with owner '$PGSQL_DB_USER'." && echo ""
    else
        echo "Error creating database '$PGSQL_DB'. Please check PostgresSQL logs or manually create and import the database." && echo ""
        exit 1
    fi
}
pgsqldb_backup_compress_encrypt() {
    local pgsql_file=$PGSQL_DB.pgsql
    local gzip_file="$pgsql_file.gzip"
    local gpg_file="$BACKUP_DIR_LOCAL/db/$gzip_file.gpg"

    echo "=========>> Exporting, Compressing & Encrypting PostgresSQL DB ($PGSQL_DB) ... =========>>" && echo ""
    start_time=$SECONDS
    cd /tmp
    sudo -H -u postgres pg_dump -d "$PGSQL_DB" --blobs --verbose -Ft | gzip > "/tmp/$gzip_file"
    #docker exec -u postgres -t "$PGSQL_CONTAINER" pg_dump -d "$PGSQL_DB" --blobs --verbose -Ft | gzip > "/tmp/$gzip_file"
    echo ""
    mkdir -p "$BACKUP_DIR_LOCAL/db"
    encrypt_file "/tmp/$gzip_file" "$gpg_file" "$PASSPHRASE"
    mv "/tmp/$gzip_file" "$BACKUP_DIR_LOCAL/db/"
    echo "<<========= PostgresSQL DB ($PGSQL_DB) Exported, Compressed and Encrypted! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}
pgsqldb_decrypt_decompress_restore() {
    local pgsql_file=$PGSQL_DB.pgsql
    local gzip_file="$pgsql_file.gzip"
    local gpg_file="$BACKUP_DIR_REMOTE/db/$gzip_file.gpg"

    echo "=========>> Decrypting, Decompressing & Importing PostgresSQL DB ($PGSQL_DB) ... =========>>" && echo ""
    start_time=$SECONDS
    if database_exists; then
        drop_database
    fi
    decrypt_file "$gpg_file" "/tmp/$gzip_file" "$PASSPHRASE"
    create_database
    cd /tmp
    # note the trailing -, which directs pg_restore to read from standard input, which is where the output of gunzip is being piped
    gunzip -c "/tmp/$gzip_file" | sudo -u postgres pg_restore -d "$PGSQL_DB" --verbose -
    #gunzip -c "/tmp/$gzip_file" | docker exec -u postgres -i "$PGSQL_CONTAINER" pg_restore -d "$PGSQL_DB" --verbose
    if [ "$?" -eq 0 ]; then
        echo "Database '$PGSQL_DB' restored successfully. Setting owner to '$PGSQL_DB_USER'..." && echo ""
    else
        echo "Error restoring database '$PGSQL_DB'. Please check PostgresSQL logs or manuall restore the database!" && echo ""
        exit 1
    fi
    rm "/tmp/$gzip_file"
    echo "<<========= PostgresSQL DB ($PGSQL_DB) Decrypted, Decompress and Imported! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

##  --- Functions for other directories/files ---
# Compress and Encrypt each file (excluding 'backups') before upload - For ex. data, etc, logs directories and files in the SWDIR
compress_encrypt_others() {
    echo ""
    echo "=========>> Compressing and encrypting other top level directories & files for upload... <<=========" && echo ""
    start_time=$SECONDS
    # Top Level Directories in SWDIR
    find "$SWDIR" -maxdepth 1 -type d ! -path "$SWDIR" ! -path "$SWDIR/$BACKUP_PREFIX" | while read -r dir; do
        local dir_name=$(basename "$dir")
        local gzip_file="$BACKUP_DIR_LOCAL/tld_$dir_name.gzip"
        local gpg_file="$gzip_file.gpg"

        # Tar and gzip the directory
        echo "Compressing Directory: $dir_name ..."
        tar -czf "$gzip_file" -C "$SWDIR" "$dir_name"
        # Encrypt the gzipped tarball
        echo "Encrypting Directory: $dir_name ..." && echo ""
        encrypt_file "$gzip_file" "$gpg_file" "$PASSPHRASE"
        #rm "$gzip_file"
    done
    # Top Level Files in SWDIR
    find "$SWDIR" -maxdepth 1 -type f | while read -r file; do
        local file_name=$(basename "$file")
        local gzip_file="$BACKUP_DIR_LOCAL/tlf_$file_name.gzip"
        local gpg_file="$gzip_file.gpg"

        # Gzip the file
        echo "Compressing File: $file_name ..."
        gzip -c "$file" > "$gzip_file"
        # Encrypt the gzipped tarball
        echo "Encrypting File: $file_name ..." && echo ""
        encrypt_file "$gzip_file" "$gpg_file" "$PASSPHRASE"
    done
    echo "<<========= Compression and encryption of other top level directories & files completed! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}
# Decrypt and Decompress downloaded files
decrypt_decompress_others() {
    echo ""
    echo "=========>> Decrypting and decompressing the downloaded - other top level directories & files... <<=========" && echo ""
    start_time=$SECONDS
    # Top-level Directories in SWDIR - additional easily accessible backup
    find "$SWDIR" -maxdepth 1 -type d ! -path "$SWDIR" ! -path "$SWDIR/$BACKUP_PREFIX" | while read -r dir; do
        local dir_name_local=$(basename "$dir")
        mv "$SWDIR/$dir_name_local" "$SWDIR/$dir_name_local.old"
    done
    # Top-level files in SWDIR - additional easily accessible backup
    find "$SWDIR" -maxdepth 1 -type f | while read -r file; do
        local file_name=$(basename "$file")
        mv "$SWDIR/$file_name" "$SWDIR/$file_name.old"
    done
    find "$BACKUP_DIR_REMOTE" -maxdepth 1 -type f -name "*.gzip.gpg" | while read -r gpg_file; do
        local base_name=$(basename "$gpg_file")
        local gzip_file="$BACKUP_DIR_REMOTE/${base_name%.gpg}"

        # Decrypt the gzipped file
        echo "Decrypting $base_name..."
        decrypt_file "$gpg_file" "$gzip_file" "$PASSPHRASE"

        # Correctly get the original file/directory name
        local original_name="${base_name%.gzip.gpg}"
        
        # Conditional logic to handle tarballs (directories) and single files
        if [[ "$original_name" == tld_* ]]; then
            local dir_name="${original_name#tld_}"
            echo "Extracting directory backup of '$dir_name'..."
            tar -xzf "$gzip_file" -C "$SWDIR"
        elif [[ "$original_name" == tlf_* ]]; then
            local file_name="${original_name#tlf_}"
            echo "Extracting file backup of '$file_name'..."
            # Gunzip and extract the file to the correct location
            gunzip -c "$gzip_file" > "$SWDIR/$file_name"
        else
            echo "Warning: Unrecognized file prefix for '$original_name'. Skipping extraction."
        fi
    done
    echo "<<========= Decryption and decompression of the downloaded -  other top level directories & files completed! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""
}

# --- Main Script ---
SECONDS=0 # Start the master timer
if [[ ! "$MODE" == "restore" ]]; then
    # Backup Logic
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>"
    echo "===>      Initiating Stalwart Mail Server Backup.      ===>"
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>" && echo ""

    ## 1. Start Docker Container if not running already
    docker_start
    sleep 5

    ## 2. Export and encrypt each individual account & Stop Docker Container
    echo "=========>> Exporting, Compressing & Encrypting Accounts... =========>>" && echo ""
    start_time=$SECONDS
    for account in "${ACCOUNTS[@]}"; do
        export_account "$account"
    done
    echo "<<========= Accounts Exported, Compressed and Encrypted! (in $((SECONDS - start_time)) seconds) <<=========" && echo ""

    docker_stop
    sleep 3
    
    ## 3. Stalwart PostgresSQL DB Backup
    pgsqldb_backup_compress_encrypt
    sleep 5

    ## 4. Compress & Encrypt other top level folders & Start Docker Container
    compress_encrypt_others
    sleep 5 && echo ""

    docker_start
    sleep 3
    
    ## 5. Rclone Sync only encrypted files
    echo "=========>> Initiating Rclone Sync: $SWSERVER --> R2... =========>>" && echo ""
    start_time=$SECONDS
    run_rclone sync -v --filter "+ *.gzip.gpg" --filter "- *" "$BACKUP_DIR_LOCAL" "$RCLONE_REMOTE_NAME"
    sleep 5
    echo "<<========= Rclone Sync to R2 Completed: $SWSERVER --> R2. (in $((SECONDS - start_time)) seconds)<<=========" && echo ""

    ## 6. Final cleanup
    echo "=========>> Cleaning up... =========>>"
    # Delete GZIP Files only if -k flag was used
    if [ -z "$KEEP_GZIP_FILES" ]; then
        find "$BACKUP_DIR_LOCAL" -name "*.gpg" -delete -o -name "*.gzip" -print -delete
    else
        find "$BACKUP_DIR_LOCAL" -name "*.gpg" -print -delete
    fi
    echo "<<========= Cleanup Completed. <<=========" && echo ""
    echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <==="
    echo "<===      Stalwart Mail Server Backup Completed. Goodbye!      <=== (in $SECONDS seconds)"
    echo "<=== <=== <== <=== <=== <=== <=== <=== <=== <=== <== <=== <=== <===" && echo ""
    exit 0

else
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>"
    echo "===>      Initiating Stalwart Mail Server Restore.     ===>"
    echo "===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===> ===>" && echo ""

    ## 0. Backup Locally (without Rclone Sync to R2) to $BACKUP_DIR_LOCAL before Restore Logic
    docker_start
    sleep 3
    for account in "${ACCOUNTS[@]}"; do
        export_account "$account"
    done
    sleep 3
    docker_stop
    sleep 3 && echo ""
    pgsqldb_backup_compress_encrypt
    sleep 5 && echo ""
    compress_encrypt_others
    sleep 5

    ## 1. Rclone Sync  only encrypted files and Stop Docker Container
    echo "=========>> Initiating Rclone Sync: $SWSERVER <-- R2... =========>>" && echo ""
    start_time=$SECONDS
    run_rclone sync -v --filter "+ *.gzip.gpg" --filter "- *" "$RCLONE_REMOTE_NAME" "$BACKUP_DIR_REMOTE"
    sleep 5
    echo "<<========= Rclone Sync Completed: $SWSERVER <-- R2. (in $((SECONDS - start_time)) seconds)<<=========" && echo ""

    docker_stop
    sleep 3 && echo ""

	## 2. Decrypt & Decompress other top level folders
    decrypt_decompress_others
    sleep 5 && echo ""

    ## 3. Stalwart PostgresSQL DB Restoration & Start Docker Container
    pgsqldb_decrypt_decompress_restore
    sleep 5 && echo ""

    docker_start
    sleep 3

    ## 4. Import Accounts
    echo "=========>> Decrypting, Decompressing & Importing Accounts... =========>>"
    start_time=$SECONDS
    for account in "${ACCOUNTS[@]}"; do
        import_account "$account"
    done
    sleep 3
    echo "<<========= Accounts Decrypted, Decompressed and Imported! (in $((SECONDS - start_time)) seconds)<<=========" && echo ""

    # 5. Final cleanup
    echo "=========>> Cleaning up... =========>>"
    # Delete GZIP Files only if -k flag was used
    if [ -z "$KEEP_GZIP_FILES" ]; then
        find "$BACKUP_DIR_REMOTE" -name "*.gpg" -delete -o -name "*.gzip" -print -delete
    else
        find "$BACKUP_DIR_REMOTE" -name "*.gpg" -print -delete
    fi
    echo "<<========= Cleanup Completed. <<=========" && echo ""
    echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <==="
    echo "<===      Stalwart Mail Server Restore Completed.      <=== (in $SECONDS seconds)"
    echo "<=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <=== <===" && echo ""
    echo "!!! Remember to remove $SWDIR/*.old directories after verifying All is Good. !!!"
    echo "=== === ^^^ Goodbye! ^^^ === ===" && echo ""
    exit 0
