# This script updates Cloudflare TLSA records by fetching DANE information directly from a Stalwart Mail Server Docker container.
# This script may be used to invoke via system cron every month

# Usage Instructions:
# Create a local bash script file Simply execute the command below or create a local bash script to do so
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/stalwart/cloudflare-tlsa-record-updater.sh | bash


# Important:
      # TLSA record must contain HOSTNAME of the Mail Server running Stalwart (in this ex. amdvps), regardless of number of email domains the mail server caters to.
      # If you've multiple Stalwart Mail servers, feel free to modify this script accordingly - changes would possibly include logic for additional variable HOSTNAME (for multiple hostnames) and appropriately updated DOMAIN_LIST
      # Stalwart Settings > Network > Host Name is configred as amdvps.domain1.tld
      # Dane best practice recommends usage of only '2 0 1' and '3 1 1' TLSA records. Lines 229 - 230 can be modified/expanded for additional TLSA records, if desired.
      # Hence the TLSA records on the Mail Server root domain (in our case domain1.tld) would be as below:
        # _25._tcp.amdvps  IN  TLSA  2 0 1 "<encrypted_cert_string>"
        # _25._tcp.amdvps  IN  TLSA  3 1 1 "<encrypted_cert_string>"
      # The script auto installs openssl and jq packages on respective distro's

#!/bin/bash

# --- Configuration ---
CLOUDFLARE_API_TOKEN="My_Cloudflare_API_Token"
SWSERVER="amdvps" # HOST NAME (non-fqdn) of the Stalwart Instance; presumed to be same/common name for multiple instances/hosts, if any
DOMAIN_LIST=("doamin1.tld")
# Adjust this space seprated list for all your email server domains (ONLY one per stalwart instance)


# --- Functions ---

# Function to install a package on Debian/Ubuntu systems
install_debian() {
    local package_name="$1"
    echo "Attempting to install ${package_name} using apt..."
    sudo apt update && sudo apt install -y "${package_name}"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to install ${package_name} using apt. Please install it manually." >&2
        exit 1
    fi
}

# Function to install a package on RHEL/CentOS systems
install_rhel() {
    local package_name="$1"
    echo "Attempting to install ${package_name} using yum/dnf..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y "${package_name}"
    else
        sudo yum install -y "${package_name}"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to install ${package_name} using yum/dnf. Please install it manually." >&2
        exit 1
    fi
}

# Function to install a package on Alpine Linux systems
install_alpine() {
    local package_name="$1"
    echo "Attempting to install ${package_name} using apk..."
    sudo apk add --no-cache "${package_name}"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to install ${package_name} using apk. Please install it manually." >&2
        exit 1
    fi
}

# Function to check and install a binary on the host system
check_and_install_host_binary() {
    local binary_name="$1"
    local package_name="$2" # Package name might differ from binary name (e.g., 'jq' vs 'jq')

    if ! command -v "${binary_name}" &> /dev/null; then
        echo "${binary_name} is not installed. Attempting to install..."
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case "$ID" in
                debian|ubuntu)
                    install_debian "${package_name}"
                    ;;
                centos|rhel|fedora)
                    install_rhel "${package_name}"
                    ;;
                alpine)
                    install_alpine "${package_name}"
                    ;;
                *)
                    echo "Unsupported OS for automatic ${binary_name} installation. Please install ${binary_name} manually." >&2
                    exit 1
                    ;;
            esac
        else
            echo "Could not detect OS for automatic ${binary_name} installation. Please install ${binary_name} manually." >&2
            exit 1
        fi
    fi
}


# Function to compare Stalwart and Cloudflare TLSA records
# Returns 0 if records match, 1 if they don't, and 2 on error
compare_tlsa_records() {
    local domain="$1"
    echo "" && echo "--- Comparing TLSA records for $domain ---"

    # 1. Extract/Generate TLSA records from Stalwart, filtering for 3 1 1 records
    local stalwart_records="3 1 1 $(openssl s_client \
                                      -starttls smtp \
                                      -connect ${SWSERVER}.${domain}:25 \
                                      -servername ${SWSERVER}.${domain} \
                                      -showcerts </dev/null 2>/dev/null \
                                    | openssl x509 -pubkey -noout \
                                    | openssl pkey -pubin -outform DER \
                                    | openssl dgst -sha256 -binary \
                                    | od -An -vtx1 \
                                    | tr -d ' \n')"
                                    
    # 2. Get existing TLSA records from Cloudflare, filtering for 3 1 1 records and the comment
    local ZONE_URL="https://api.cloudflare.com/client/v4/zones?name=${domain}"
    local ZONE_RESPONSE=$(curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${ZONE_URL}")
    local ZONE_ID=$(echo "${ZONE_RESPONSE}" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo "Error: Could not find Cloudflare Zone ID for domain: $domain." >&2
        return 2
    fi

    local DNS_RECORDS_URL="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=TLSA"
    local DNS_RECORDS_RESPONSE=$(curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${DNS_RECORDS_URL}")

    local cloudflare_records=$(echo "${DNS_RECORDS_RESPONSE}" | jq -r '.result[] | select((.comment // ""| contains("Managed by TLSA-updater script")) and (.data.usage == 3 and .data.selector == 1 and .data.matching_type == 1)) | .data.usage, .data.selector, .data.matching_type, .data.certificate' | paste -s -d' ' | sort)

    # 3. Compare the sorted outputs
    if [[ "$stalwart_records" == "$cloudflare_records" ]]; then
        echo "TLSA records match for $domain. No update needed."
        return 0
    else
        echo "!! TLSA records DO NOT match for $domain. !!"
        return 1
    fi
}

# Function to update TLSA records for a given domain
update_tlsa_records() {
    local domain_to_update="$1"
    local current_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local comment_text="Managed by TLSA-updater script; Last sync: ${current_timestamp}"

    echo "" && echo "--- Updating TLSA records for domain: $domain_to_update ---"

    # 1. Get the zone ID for the domain from Cloudflare
    ZONE_URL="https://api.cloudflare.com/client/v4/zones?name=${domain_to_update}"
    ZONE_RESPONSE=$(curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${ZONE_URL}")

    ZONE_ID=$(echo "${ZONE_RESPONSE}" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo "Error: Could not find Cloudflare Zone ID for domain: $domain_to_update. Response: $ZONE_RESPONSE"
        return 1
    fi
    echo "Cloudflare Zone ID for $domain_to_update: $ZONE_ID"

    # 2. Delete existing TLSA records (names of which contain '$SWSERVER') for this domain on Cloudflare
    echo "" && echo "Fetching and deleting all existing TLSA records for ${domain_to_update} on Cloudflare..." && echo ""
    DNS_RECORDS_URL="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=TLSA"
    DNS_RECORDS_RESPONSE=$(curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${DNS_RECORDS_URL}")

    if echo "${DNS_RECORDS_RESPONSE}" | jq -e '.result | type == "array"' > /dev/null; then
        echo "${DNS_RECORDS_RESPONSE}" | jq -c '.result[]' | while read -r existing_record; do
            RECORD_ID=$(echo "${existing_record}" | jq -r '.id')
            RECORD_NAME_EXISTING=$(echo "${existing_record}" | jq -r '.name') # Get existing record name for logging

            # Check if the existing record name contains '.$SWSERVER.'
            if [[ "$RECORD_NAME_EXISTING" == *".$SWSERVER."* ]]; then # <--- NEW CONDITION ADDED HERE
                DELETE_URL="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}"
                DELETE_RESPONSE=$(curl -s -X DELETE -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${DELETE_URL}")
                if echo "${DELETE_RESPONSE}" | jq -e '.success == true' > /dev/null; then
                    echo "-> Deleted TLSA record matching criteria: $RECORD_NAME_EXISTING (Record ID: $RECORD_ID)"
                else
                    echo "-> Failed to delete TLSA record: $RECORD_NAME_EXISTING (Record ID: $RECORD_ID). Response: $DELETE_RESPONSE"
                fi
            else
                echo "-> Skipping TLSA record deletion for: $RECORD_NAME_EXISTING (Does not end with '.$SWSERVER')" # <--- Added log for skipped records
            fi
        done
        echo "" && echo "Finished deleting existing TLSA records."
    else
        echo "" && echo "No existing TLSA records found or Cloudflare API response for existing records was invalid for ${domain_to_update}. Proceeding to add new records."
    fi
    
    # 3. Generate TLSA cert from SMTP TLS endpoint
    echo "" && echo "Generating TLSA records directly from live SMTP TLS endpoint..."

    local TLS_HOST="${SWSERVER}.${domain_to_update}"
    local TLS_PORT="25"

    local FINAL_RECORD_NAME="_25._tcp.${SWSERVER}.${domain_to_update}"

    # Generate 3 1 1
    local TLSA_311_CERTIFICATE=$(openssl s_client \
        -starttls smtp \
        -connect "${TLS_HOST}:${TLS_PORT}" \
        -servername "${TLS_HOST}" \
        </dev/null 2>/dev/null \
    | openssl x509 -pubkey -noout \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -vtx1 \
    | tr -d ' \n')

    # Generate 2 0 1
    TMPDIR=$(mktemp -d)
    openssl s_client \
        -starttls smtp \
        -connect "${TLS_HOST}:${TLS_PORT}" \
        -servername "${TLS_HOST}" \
        -showcerts </dev/null 2>/dev/null \
    | awk -v dir="$TMPDIR" '
        /BEGIN CERTIFICATE/ {
            certfile=sprintf("%s/cert%d.pem", dir, ++n)
        }
        certfile {
            print > certfile
        }
        /END CERTIFICATE/ {
            close(certfile)
            certfile=""
        }
    '
    TOP_CA_CERT=""
    for cert in "$TMPDIR"/cert*.pem; do
        SUBJECT=$(openssl x509 -in "$cert" -noout -subject)
        ISSUER=$(openssl x509 -in "$cert" -noout -issuer)
        # Skip leaf cert
        if openssl x509 -in "$cert" -noout -text | grep -q "CA:TRUE"; then
            # Prefer highest non-self-signed CA
            if [[ "$SUBJECT" != "$ISSUER" ]]; then
                TOP_CA_CERT="$cert"
            fi
        fi
    done
    if [[ -z "$TOP_CA_CERT" ]]; then
        echo "Error: Could not determine CA trust anchor certificate."
        rm -rf "$TMPDIR"
        return 1
    fi

    local TLSA_201_CERTIFICATE=$(openssl x509 \
        -in "$TOP_CA_CERT" \
        -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -vtx1 \
    | tr -d ' \n')

    rm -rf "$TMPDIR"

    # Define both TLSA modes
    TLSA_RECORDS=(
        "3 1 1 ${TLSA_311_CERTIFICATE}"
        "2 0 1 ${TLSA_201_CERTIFICATE}"
    )
    echo ${TLSA_RECORDS}

    # 4. Add all TLSA records from Stalwart to Cloudflare
    echo "" && echo "Adding TLSA records to Cloudflare..."

    for TLSA_RECORD in "${TLSA_RECORDS[@]}"; do
        IFS=' ' read -r USAGE SELECTOR MATCHING_TYPE CERTIFICATE <<< "$TLSA_RECORD"

        DNS_DATA=$(jq -n \
            --arg type "TLSA" \
            --arg name "$FINAL_RECORD_NAME" \
            --arg usage "$USAGE" \
            --arg selector "$SELECTOR" \
            --arg matching_type "$MATCHING_TYPE" \
            --arg certificate "$CERTIFICATE" \
            --arg comment "$comment_text" \
            '{
                type: $type,
                name: $name,
                data: {
                    usage: ($usage | tonumber),
                    selector: ($selector | tonumber),
                    matching_type: ($matching_type | tonumber),
                    certificate: $certificate
                },
                proxied: false,
                comment: $comment
            }')

        ADD_URL="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records"

        ADD_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${DNS_DATA}" \
            "${ADD_URL}")

        if echo "${ADD_RESPONSE}" | jq -e '.success == true' > /dev/null; then
            echo "-> Added TLSA record: $FINAL_RECORD_NAME (Mode: $USAGE $SELECTOR $MATCHING_TYPE)"
        else
            echo "-> Failed to add TLSA record: $FINAL_RECORD_NAME (Mode: $USAGE $SELECTOR $MATCHING_TYPE). Response: $ADD_RESPONSE"
        fi
    done

    echo "" && echo "--- TLSA update for $domain_to_update complete. ---"

}
# --- Functions ---


# --- Main Script Execution ---

echo "=================================" && echo "Starting TLSA record update process..." && echo "================================="

# 1. Verify and install 'jq' on the host machine
check_and_install_host_binary "jq" "jq"
check_and_install_host_binary "openssl" "openssl"

# 2. Compare & Update TLSA Records for each domain
CONFIRM_PROCEED="y"
for domain in "${DOMAIN_LIST[@]}"; do
    compare_tlsa_records "$domain"
    if [[ $? -eq 1 ]]; then
        read -p "$(echo "Do you want to proceed? (y/N): ")" input_confirm_proceed < /dev/tty
        CONFIRM_PROCEED="${input_confirm_proceed:-$CONFIRM_PROCEED}"
        if [[ "${CONFIRM_PROCEED,,}" == "y" ]]; then
            update_tlsa_records "$domain"
        else
            echo "" && echo "====> Script Termination Accepted <==== " && exit 0
        fi
    else
        echo "" && echo "=================================" && echo "Good-bye!" && exit 0
    fi
done

echo "" && echo "=================================" && echo "All TLSA record updates complete."

exit 0
