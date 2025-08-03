#!/bin/bash
# Newt Client Installer/Updater Script
# https://docs.fossorial.io/Newt/install#binary
# How to USE:
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/newt-installer-updater.sh | sudo bash

# ANSI color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
NC='\e[0m' # No Color

# Define the target path for the systemd service file
SERVICE_FILE="/etc/systemd/system/newt.service"
NEWT_BIN_PATH="/usr/local/bin/newt"
NEWT_LIB_PATH="/var/lib/newt"
DOCKER_SOCKET_PATH=""

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# Initialize variables to 'N' by default, assuming they are not present
NEWT_CLIENTS="N"
NEWT_NATIVE="N"
DOCKER_SOCKET="N"

# --- Capture Existing Info ---
if [[ -f "${SERVICE_FILE}" ]]; then
  # Get the ExecStart line
  exec_start_line=$(grep '^ExecStart=' "${SERVICE_FILE}")

  # Extract ID
  NEWT_ID=$(echo "${exec_start_line}" | awk -F'--id ' '{print $2}' | awk '{print $1}')
  # Extract Secret
  NEWT_SECRET=$(echo "${exec_start_line}" | awk -F'--secret ' '{print $2}' | awk '{print $1}')
  # Extract Endpoint
  PANGOLIN_ENDPOINT=$(echo "${exec_start_line}" | awk -F'--endpoint ' '{print $2}' | awk '{print $1}')

  # Check for --accept-clients, --native or --docker-socket flags
  if echo "${exec_start_line}" | grep -q -- --accept-clients; then
    NEWT_CLIENTS="y"
  fi
  if echo "${exec_start_line}" | grep -q -- --native; then
    NEWT_NATIVE="y"
  fi
  if echo "${exec_start_line}" | grep -q -- --docker-socket; then
    DOCKER_SOCKET="y"
    DOCKER_SOCKET_PATH="$(echo "${exec_start_line}" | sed -n 's/.*--docker-socket \(\S\+\).*/\1/p')"
  fi

  echo -e "Captured existing newt info from ${GREEN}${SERVICE_FILE}${NC}:"
  echo -e "  ID: ${YELLOW}${NEWT_ID}${NC}"
  echo -e "  Secret: ${YELLOW}${NEWT_SECRET}${NC}"
  echo -e "  Endpoint: ${YELLOW}${PANGOLIN_ENDPOINT}${NC}"
  echo -e "  Accept Newt/OLM Clients Access: ${YELLOW}${NEWT_CLIENTS}${NC}"
  echo -e "  Enable Newt Native Mode: ${YELLOW}${NEWT_NATIVE}${NC}"
  echo -e "  Enable Docker Socket Access: ${YELLOW}${DOCKER_SOCKET}${NC}"
  echo -e "  Docker Socket Path: ${YELLOW}${DOCKER_SOCKET_PATH}${NC}"
  echo ""

  read -p "Do you want to proceed with these values? (y/N) " CONFIRM_PROCEED < /dev/tty
  #read -p "${YELLOW}Do you want to proceed with these values? (y/N)${NC} " CONFIRM_PROCEED < /dev/tty
  #echo -e "${YELLOW}Do you want to proceed with these values? (y/N)${NC} "
  #read CONFIRM_PROCEED < /dev/tty
  if [[ ! "${CONFIRM_PROCEED}" =~ ^[Yy]$ ]]; then
    read -p "Do you want to provide New values? (y/N) " CONFIRM_PROVIDE < /dev/tty
    if [[ ! "${CONFIRM_PROVIDE}" =~ ^[Yy]$ ]]; then
      echo -e "${RED}Operation cancelled by user.${NC}"
      exit 0 # Exit cleanly if the user doesn't confirm
    else
      echo ""
      read -p "Enter the Newt Client ID: " NEWT_ID < /dev/tty
      read -p "Enter the Newt Client Secret: " NEWT_SECRET < /dev/tty
      read -p "Enter the Pangolin Endpoint (ex. https://pangolin.yourdomain.com): " PANGOLIN_ENDPOINT < /dev/tty
      read -p "Accept Newt/OLM Clients Access? (y/N): " NEWT_CLIENTS < /dev/tty
      read -p "Enable Newt Native Mode (y/N): " NEWT_NATIVE < /dev/tty
      read -p "Enable Docker Socket Access (requires Native Mode) (y/N): " DOCKER_SOCKET < /dev/tty
      if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ && "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
        read -p "Enter Docker Socket Path (ex. /var/run/docker.sock): " DOCKER_SOCKET_PATH < /dev/tty
      fi
      echo ""
    fi
  fi
  echo ""
# --- or Capture User Input ---
else
  echo ""
  read -p "Enter the Newt Client ID: " NEWT_ID < /dev/tty
  read -p "Enter the Newt Client Secret: " NEWT_SECRET < /dev/tty
  read -p "Enter the Pangolin Endpoint (ex. https://pangolin.yourdomain.com): " PANGOLIN_ENDPOINT < /dev/tty
  read -p "Accept Newt/OLM Clients Access? (y/N): " NEWT_CLIENTS < /dev/tty
  read -p "Enable Newt Native Mode (y/N): " NEWT_NATIVE < /dev/tty
  read -p "Enable Docker Socket Access (requires Native Mode) (y/N): " DOCKER_SOCKET < /dev/tty
  if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ && "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
    read -p "Enter Docker Socket Path (ex. /var/run/docker.socket): " DOCKER_SOCKET_PATH < /dev/tty
  fi
  echo ""
fi

# --- Newt Binary Download and Update Section ---
echo ""
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
    echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
    echo -e "${RED}This script supports amd64 and arm64.${NC}"
    exit 1
    ;;
esac
echo ""
echo "Detected architecture: $ARCH ($NEWT_ARCH)"

# Get the latest release tag from GitHub API
# Use -s for silent, -L for follow redirects
LATEST_RELEASE_URL=$(curl -sL "https://api.github.com/repos/fosrl/newt/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE_URL" ]; then
  echo -e "${RED}Error: Could not fetch latest Newt release tag from GitHub.${NC}"
  exit 1 # Exit if we can't get the latest version tag
else
  echo -e "${GREEN}Latest release tag found: $LATEST_RELEASE_URL${NC}"
  # Construct the download URL using the found tag name and detected architecture
  DOWNLOAD_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_URL}/newt_linux_${NEWT_ARCH}"

  # Check if the binary already exists and is the latest version (optional but good practice)
  # This part is complex without knowing the installed version, so we'll just download and replace
  # if [ -f "$NEWT_BIN_PATH" ] && "$NEWT_BIN_PATH" --version 2>/dev/null | grep -q "$LATEST_RELEASE_URL"; then
  #   echo "Newt binary is already the latest version ($LATEST_RELEASE_URL). Skipping download."
  # else
    echo -e "Attempting to download ${YELLOW}Newt binary for ${ARCH}${NC} from $DOWNLOAD_URL"
    if ! wget -O /tmp/newt_temp "$DOWNLOAD_URL"; then
      echo -e "${RED}Error: Failed to download Newt binary from $DOWNLOAD_URL.${NC}"
      echo -e "${YELLOW}Please check the URL and your network connection.${NC}"
      exit 1
    fi

    echo -e "Installing ${GREEN}Newt binary to $NEWT_BIN_PATH${NC}"
    chmod +x /tmp/newt_temp
    mv /tmp/newt_temp "$NEWT_BIN_PATH"
    echo -e "${GREEN}Newt binary updated successfully.${NC}"
    echo ""
  # fi
fi

# --- End of Newt Binary Section ---

# Initialize ExecStartValue
ExecStartValue="/usr/local/bin/newt --id ${NEWT_ID} --secret ${NEWT_SECRET} --endpoint ${PANGOLIN_ENDPOINT}"

# Conditionally add --accept-clients, --native or --docker-socket flags
if [[ "${NEWT_CLIENTS}" =~ ^[Yy]$ ]]; then
    ExecStartValue="${ExecStartValue} --accept-clients"
fi
if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ && "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
    ExecStartValue="${ExecStartValue} --docker-socket ${DOCKER_SOCKET_PATH}"
fi
if [[ "${NEWT_NATIVE}" =~ ^[Yy]$ ]]; then
    read -r -d '' SERVICE_CONTENT << EOF1
[Unit]
Description=Newt VPN Client Service (Native Mode)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${ExecStartValue} --native
Restart=always
RestartSec=10

# Security hardening options
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF1
else
    read -r -d '' SERVICE_CONTENT << EOF2
[Unit]
Description=Newt VPN Client Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${ExecStartValue}
Restart=always
RestartSec=10

# Security hardening options
User=newt
Group=newt
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ReadWritePaths=${NEWT_LIB_PATH}

[Install]
WantedBy=multi-user.target
EOF2
    # Create the directory for the newt user and group if they don't exist
    getent group newt >/dev/null || groupadd newt
    getent passwd newt >/dev/null || useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
    mkdir -p "${NEWT_LIB_PATH}"
    chown newt:newt "${NEWT_LIB_PATH}"
fi

# Write the content to the service file
echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null

echo -e "Systemd service file created at ${GREEN}$SERVICE_FILE${NC} with provided NEWT VPN Client details."
echo -e "${YELLOW}Now, reloading systemd,  enabling/starting the service:${NC}"
systemctl daemon-reload
systemctl enable newt.service
systemctl start newt.service
systemctl status newt.service | cat
