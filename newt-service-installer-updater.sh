#!/bin/bash
# Newt VPN Client Installer/Updater Script for Debain - as a Service unit
# https://docs.fossorial.io/Newt/install#binary
# How to USE:
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/newt-service-installer-updater.sh | sudo bash
#
# Assumptions:
# 1. A group named docker exists with Read/Write Permissions to the Docker Socket file

# ANSI color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
BOLD='\e[1m'
ITALIC='\e[3m'
NC='\e[0m' # No Color

# Define the target path for the systemd service file
SERVICE_NAME="newt.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
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
  # 
  prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_input
    read -p "$(echo -e "${BOLD}$prompt${NC} or hit enter to use (${BOLD}${GREEN}$default${NC}): ")" var_input < /dev/tty
    echo "${var_input:-$default}"
  }
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

  echo -e "${BOLD}==================================================================${NC}"
  echo -e "${BOLD}Captured existing Newt info from ${ITALIC}${GREEN}${SERVICE_FILE}${NC}:"
  echo -e "${BOLD}==================================================================${NC}"
  echo -e "  ID: ${ITALIC}${YELLOW}${NEWT_ID}${NC}"
  echo -e "  Secret: ${ITALIC}${YELLOW}${NEWT_SECRET}${NC}"
  echo -e "  Endpoint: ${ITALIC}${YELLOW}${PANGOLIN_ENDPOINT}${NC}"
  echo -e "  Accept Newt/OLM Clients Access: ${ITALIC}${YELLOW}${NEWT_CLIENTS}${NC}"
  echo -e "  Enable Newt Native Mode: ${ITALIC}${YELLOW}${NEWT_NATIVE}${NC}"
  echo -e "  Enable Docker Socket Access: ${ITALIC}${YELLOW}${DOCKER_SOCKET}${NC}"
  echo -e "  Docker Socket Path: ${ITALIC}${YELLOW}${DOCKER_SOCKET_PATH}${NC}"
  echo -e "${BOLD}==================================================================${NC}"
  echo ""

  read -p "$(echo -e "${BOLD}Upgrade${NC} to latest version or ${BOLD}Remove${NC} Newt? ${YELLOW}${BOLD}(u/R)${NC}: ")" CONFIRM_UPGRADE_REMOVE < /dev/tty
  if [[ ! "${CONFIRM_UPGRADE_REMOVE}" =~ ^[Rr]$ ]]; then
      read -p "$(echo -e "Proceed with ${BOLD}ALL the existing${NC} values? ${YELLOW}${BOLD}(y/N)${NC}: ")" CONFIRM_PROCEED < /dev/tty
      if [[ ! "${CONFIRM_PROCEED}" =~ ^[Yy]$ ]]; then
        read -p "$(echo -e "Provide ${BOLD}New${NC} values? ${YELLOW}${BOLD}(y/N)${NC}: ")" CONFIRM_PROVIDE < /dev/tty
        if [[ ! "${CONFIRM_PROVIDE}" =~ ^[Yy]$ ]]; then
          echo -e "${RED}Operation cancelled by user.${NC}"
          exit 0 # Exit cleanly if the user doesn't confirm
        else
          echo ""
          echo -e "${YELLOW}Initiating Newt Service Re-installation...${NC}"
          #read -p "Provide Newt Client ID. or hit enter to use ($NEWT_ID): " NEWT_ID_input < /dev/tty
          #NEWT_ID="${NEWT_ID_input:-$NEWT_ID}"
          NEWT_ID=$(prompt_with_default "Provide Newt Client ID." "$NEWT_ID")
          
          #read -p "Provide Newt Client Secret. or hit enter to use ($NEWT_SECRET): " NEWT_SECRET_input < /dev/tty
          #NEWT_SECRET="${NEWT_SECRET_input:-$NEWT_SECRET}"
          NEWT_SECRET=$(prompt_with_default "Provide Newt Client Secret." "$NEWT_SECRET")
          
          #read -p "Provide Pangolin Endpoint. or hit enter to use ($PANGOLIN_ENDPOINT): " PANGOLIN_ENDPOINT_input < /dev/tty
          #PANGOLIN_ENDPOINT="${PANGOLIN_ENDPOINT_input:-$PANGOLIN_ENDPOINT}"
          PANGOLIN_ENDPOINT=$(prompt_with_default "Provide Pangolin Endpoint." "$PANGOLIN_ENDPOINT")
          
          read -p "$(echo -e "Enable ${BOLD}Docker Socket${NC} Access ${YELLOW}${BOLD}${ITALIC}(y/N)${NC}: ")" DOCKER_SOCKET < /dev/tty
          if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]]; then
            #read -p "Provide Docker Socket Path. or hit enter to use ($DOCKER_SOCKET_PATH): " DOCKER_SOCKET_PATH_input < /dev/tty
            #DOCKER_SOCKET_PATH="${DOCKER_SOCKET_PATH_input:-$DOCKER_SOCKET_PATH}"
            DOCKER_SOCKET_PATH=$(prompt_with_default "Provide Docker Socket Path." "$DOCKER_SOCKET_PATH")
          fi
          read -p "$(echo -e "Enable ${BOLD}OLM Clients${NC} Access? ${YELLOW}${BOLD}${ITALIC}(y/N)${NC}: ")" NEWT_CLIENTS < /dev/tty
          read -p "$(echo -e "Enable ${BOLD}Native${NC} Mode ${YELLOW}${BOLD}${ITALIC}(y/N)${NC}: ")" NEWT_NATIVE < /dev/tty
        fi
      fi
  else
      # --- Newt Service Removal ---
      systemctl stop $SERVICE_NAME
      systemctl disable $SERVICE_NAME
      rm /etc/systemd/system/$SERVICE_NAME
      systemctl daemon-reload
      getent passwd newt >/dev/null && userdel -r newt
      getent group newt >/dev/null && groupdel newt
      rm -rf "${NEWT_LIB_PATH}"
      rm "$NEWT_BIN_PATH"
      echo -e "${YELLOW}Removed Newt user, group and service. Goodbye!${NC}"
      exit 0
  fi
  echo ""
# --- or Capture User Input for First Time Service Installation ---
else
  echo ""
  echo -e "${YELLOW}Initiating Newt Service Installation...${NC}"
  read -p "$(echo -e "Provide Newt ${BOLD}Client ID${NC}: ")" NEWT_ID < /dev/tty
  read -p "$(echo -e "Provide Newt ${BOLD}Client Secret${NC}: ")" NEWT_SECRET < /dev/tty
  read -p "$(echo -e "Provide ${BOLD}Pangolin Endpoint${NC} (ex. ${ITALIC}https://pangolin.yourdomain.com${NC}): ")" PANGOLIN_ENDPOINT < /dev/tty
  read -p "$(echo -e "Enable ${BOLD}Docker Socket${NC} Access ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" DOCKER_SOCKET < /dev/tty
  if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "Provide ${BOLD}Docker Socket Path${NC} (ex. ${ITALIC}/var/run/docker.sock${NC}): ")" DOCKER_SOCKET_PATH < /dev/tty
  fi
  read -p "$(echo -e "Enable ${BOLD}OLM Clients${NC} Access? ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" NEWT_CLIENTS < /dev/tty
  read -p "$(echo -e "Enable ${BOLD}Native${NC} Mode ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" NEWT_NATIVE < /dev/tty
  echo ""
fi

# --- Newt Binary Download and Update Section ---
echo ""
echo -e "${YELLOW}Checking for the latest Newt binary...${NC}"

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
echo -e "Detected architecture: ${YELLOW}$ARCH ($NEWT_ARCH)${NC}"

# Get the latest release tag from GitHub API
# Use -s for silent, -L for follow redirects
LATEST_RELEASE_TAG=$(curl -sL "https://api.github.com/repos/fosrl/newt/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
RELEASE_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_TAG}/newt_linux_${NEWT_ARCH}"
if [ -z "${RELEASE_URL}" ]; then
  echo -e "${RED}Error: Could not fetch Newt release url from GitHub.${NC}"
  exit 1 # Exit if we can't get the latest version tag
else
  echo -e "New release url found: ${YELLOW}$RELEASE_URL${NC}"
  # Construct the download URL using the found tag name and detected architecture
  #DOWNLOAD_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_URL}/newt_linux_${NEWT_ARCH}"
  DOWNLOAD_URL="${RELEASE_URL}"
  # Check if the binary already exists and is the latest version (optional but good practice)
  # This part is complex without knowing the installed version, so we'll just download and replace
  # if [ -f "$NEWT_BIN_PATH" ] && "$NEWT_BIN_PATH" --version 2>/dev/null | grep -q "$LATEST_RELEASE_URL"; then
  #   echo "Newt binary is already the latest version ($LATEST_RELEASE_URL). Skipping download."
  # else
    echo -e "Attempting to download ${YELLOW}Newt binary for ${ARCH}${NC}..."
    if ! wget -q -O /tmp/newt_temp -L "$DOWNLOAD_URL"; then
      echo -e "${RED}Error: Failed to download Newt binary from $DOWNLOAD_URL.${NC}"
      echo -e "${YELLOW}Please check the URL and your network connection.${NC}"
      exit 1
    fi
    echo -e "=== ${GREEN}Download Complete${NC} ==="
    echo ""
    echo -e "Installing ${GREEN}Newt binary${NC} to ${GREEN}$NEWT_BIN_PATH${NC}"
    chmod +x /tmp/newt_temp
    mv /tmp/newt_temp "$NEWT_BIN_PATH"
    echo -e "${GREEN}Newt binary${NC} installed successfully."
    echo ""
  # fi
fi

# --- End of Newt Binary Section ---

# Initialize ExecStartValue
ExecStartValue="/usr/local/bin/newt --id ${NEWT_ID} --secret ${NEWT_SECRET} --endpoint ${PANGOLIN_ENDPOINT}"

# Conditionally add --accept-clients, --native or --docker-socket flags - ONLY for Upgrade Choice
if [[ "${NEWT_CLIENTS}" =~ ^[Yy]$ ]]; then
    ExecStartValue="${ExecStartValue} --accept-clients"
fi
if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ && -n "${DOCKER_SOCKET_PATH}" ]]; then
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
    if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]] && getent group docker >/dev/null; then
        getent passwd newt >/dev/null || useradd -r -g newt -G docker -s /usr/sbin/nologin -c "Newt Service User" newt
    elif [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]] && ! getent group docker >/dev/null; then
        getent passwd newt >/dev/null || useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
        echo -e "Although standard ${RED}docker${NC} group not found, ${GREEN}Newt${NC} user is (re)created. ${RED}REMEMBER${NC} to add it to your ${YELLOW}custom docker${NC} group!"
    else
        getent passwd newt >/dev/null || useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
    fi
    mkdir -p "${NEWT_LIB_PATH}"
    chown newt:newt "${NEWT_LIB_PATH}"
fi

# Write the content to the service file
echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null
echo -e "Systemd service file (re)created at ${GREEN}$SERVICE_FILE${NC} with provided NEWT VPN Client details."
echo ""
echo -e "${YELLOW}Enabling/Starting the service:${NC}"
systemctl stop $SERVICE_NAME
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
systemctl status $SERVICE_NAME | cat
echo ""
echo -e "${GREEN}Newt VPN Client Service installed. Goodbye!${NC}"
exit 0
