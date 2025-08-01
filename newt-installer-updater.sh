#!/bin/bash
# Newt Client Installer/Updater Script
# https://docs.fossorial.io/Newt/install#binary
# How to USE:
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/newt-installer-updater.sh | sudo bash
# sudo rm newt-installer-updater.sh

# Define the target path for the systemd service file
SERVICE_FILE="/etc/systemd/system/newt.service"
NEWT_BIN_PATH="/usr/local/bin/newt"
NEWT_LIB_PATH="/var/lib/newt"

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# --- Newt Binary Download and Update Section ---
echo "Checking for the latest Newt binary..."

# Detect system architecture
ARCH=$(dpkg --print-architecture) # Common command on Debian/Ubuntu-based systems

case "$ARCH" in
  amd64)
    NEWT_ARCH="amd64"
    ;;
  arm64)
    NEWT_ARCH="arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    echo "This script supports amd64 and arm64."
    exit 1
    ;;
esac

echo "Detected architecture: $ARCH ($NEWT_ARCH)"

# Get the latest release tag from GitHub API
# Use -s for silent, -L for follow redirects
LATEST_RELEASE_URL=$(curl -sL "https://api.github.com/repos/fosrl/newt/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE_URL" ]; then
  echo "Error: Could not fetch latest Newt release tag from GitHub."
  exit 1 # Exit if we can't get the latest version tag
else
  echo "Latest release tag found: $LATEST_RELEASE_URL"
  # Construct the download URL using the found tag name and detected architecture
  DOWNLOAD_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_URL}/newt_linux_${NEWT_ARCH}"

  # Check if the binary already exists and is the latest version (optional but good practice)
  # This part is complex without knowing the installed version, so we'll just download and replace
  # if [ -f "$NEWT_BIN_PATH" ] && "$NEWT_BIN_PATH" --version 2>/dev/null | grep -q "$LATEST_RELEASE_URL"; then
  #   echo "Newt binary is already the latest version ($LATEST_RELEASE_URL). Skipping download."
  # else
    echo "Attempting to download Newt binary for ${ARCH} from $DOWNLOAD_URL"
    if ! wget -O /tmp/newt_temp "$DOWNLOAD_URL"; then
      echo "Error: Failed to download Newt binary from $DOWNLOAD_URL."
      echo "Please check the URL and your network connection."
      exit 1
    fi

    echo "Installing Newt binary to $NEWT_BIN_PATH"
    chmod +x /tmp/newt_temp
    mv /tmp/newt_temp "$NEWT_BIN_PATH"
    echo "Newt binary updated successfully."
  # fi
fi

# --- End of Newt Binary Section ---

# Prompt the user for the Newt client configuration values
read -p "Enter the Newt Client ID: " NEWT_ID < /dev/tty
read -p "Enter the Newt Client Secret: " NEWT_SECRET < /dev/tty
read -p "Enter the Pangolin Endpoint (e.g., https://pangolin.yourdomain.com): " PANGOLIN_ENDPOINT < /dev/tty
read -p "Accept Newt/OLM Clients?: (y/N) " NEWT_CLIENTS < /dev/tty
read -p "Enable Newt Native Mode: (y/N) " NEWT_NATIVE < /dev/tty

# Initialize Service Unit Parameters
ExecStartData="/usr/local/bin/newt --id ${NEWT_ID} --secret ${NEWT_SECRET} --endpoint ${PANGOLIN_ENDPOINT} --docker-socket /var/run/docker.sock"
User=newt
Group=newt
NoNewPrivileges=yes

# Conditionally add --accept-clients
if [[ "${NEWT_CLIENTS}" =~ ^[Yy]$ ]]; then
    ExecStartData="${ExecStartData} --accept-clients"
fi

# Conditionally add --native
if [[ "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
    ExecStartData="${ExecStartData} --native"
    User=root
    Group=root
    NoNewPrivileges=no
fi

# Define the content of the service file using a here-document
# Use the variables populated by user input
read -r -d '' SERVICE_CONTENT << EOF
[Unit]
Description=Newt Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart="${ExecStartData}"
Restart=always
RestartSec=10

# Security hardening options
User="$User"
Group="$Group"
NoNewPrivileges="$NoNewPrivileges"
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadWritePaths=${NEWT_LIB_PATH}

[Install]
WantedBy=multi-user.target
EOF

# Create the directory for the newt user and group if they don't exist
getent group newt >/dev/null || groupadd newt
getent passwd newt >/dev/null || useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
mkdir -p "${NEWT_LIB_PATH}"
if [[ "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
  chown root:root "${NEWT_LIB_PATH}"
else
  chown newt:newt "${NEWT_LIB_PATH}"
fi

# Write the content to the service file
echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null

echo "Systemd service file created at $SERVICE_FILE with provided details."
echo "Now, reloading systemd,  enabling/starting the service:"
systemctl daemon-reload
systemctl enable newt.service
systemctl start newt.service
systemctl status newt.service
