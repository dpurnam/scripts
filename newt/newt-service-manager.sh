#!/bin/bash
# Newt Client Service Manager (Removal/Installer/Updater) Script for Debain - as a Service unit
# REF: https://docs.fossorial.io/Newt

# Usage Instructions:
# Create a local bash script file Simply execute the command below or create a local bash script to do so
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/newt/newt-service-manager.sh | sudo bash

# Assumptions:
# A group named docker exists with Read/Write Permissions to the Docker Socket file

#set -euo pipefail

# Get the 'latest' release tag for the newt client, from GitHub API
LATEST_RELEASE_TAG=$(curl -fsSL https://api.github.com/repos/fosrl/newt/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p')

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
  echo -e "${RED}${BOLD}Please run this script with sudo.${NC}"
  exit 1
fi

# Initialize variables
NEWT_CLIENTS="Y"
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
  SITE_ID=$(echo "${exec_start_line}" | awk -F'--id ' '{print $2}' | awk '{print $1}')
  # Extract Secret
  SITE_SECRET=$(echo "${exec_start_line}" | awk -F'--secret ' '{print $2}' | awk '{print $1}')
  # Extract Endpoint
  PANGOLIN_ENDPOINT=$(echo "${exec_start_line}" | awk -F'--endpoint ' '{print $2}' | awk '{print $1}')
  # Get current binary version
  #INSTALLED_VERSION="$("$NEWT_BIN_PATH" -version 2>/dev/null | awk '{print $3}')"
  INSTALLED_VERSION="$(newt -version 2>/dev/null | awk '{print $3}')"

  # Check for --accept-clients, --native or --docker-socket flags
  if [[ $exec_start_line == *"--accept-clients"* ]]; then
      NEWT_CLIENTS="y"
  elif [[ ${exec_start_line,,} == *"--disable-clients true"* ]]; then
      NEWT_CLIENTS="n"
  fi

  if [[ $exec_start_line == *"--native"* ]]; then
    NEWT_NATIVE="y"
  fi

  if [[ $exec_start_line =~ --docker-socket[[:space:]]+\"?([^\"[:space:]]+)\"? ]]; then
      DOCKER_SOCKET="y"
      DOCKER_SOCKET_PATH="${BASH_REMATCH[1]}"
  fi

  echo -e "${BOLD}==================================================================${NC}"
  echo -e "${BOLD}Captured existing Newt info from ${ITALIC}${GREEN}${SERVICE_FILE}${NC}:"
  echo -e "${BOLD}==================================================================${NC}"
  echo -e "  Site ID: ${ITALIC}${YELLOW}${SITE_ID}${NC}"
  echo -e "  Site Secret: ${ITALIC}${YELLOW}${SITE_SECRET}${NC}"
  echo -e "  Endpoint: ${ITALIC}${YELLOW}${PANGOLIN_ENDPOINT}${NC}"
  echo -e "  Enable Pangolin/OLM Clients Access: ${ITALIC}${YELLOW}${NEWT_CLIENTS}${NC}"
  echo -e "  Enable Newt Native Mode: ${ITALIC}${YELLOW}${NEWT_NATIVE}${NC}"
  echo -e "  Enable Docker Socket Access: ${ITALIC}${YELLOW}${DOCKER_SOCKET}${NC}"
  echo -e "  Docker Socket Path: ${ITALIC}${YELLOW}${DOCKER_SOCKET_PATH}${NC}"
  echo -e "${BOLD}==================================================================${NC}"
  echo ""

  read -p "$(echo -e "${BOLD}Upgrade${NC} to latest version (${LATEST_RELEASE_TAG}) or ${BOLD}Remove${NC} the current one (${INSTALLED_VERSION:-unknown})? ${BOLD}${ITALIC}${YELLOW}[${GREEN}u${YELLOW}/${RED}R${YELLOW}]${NC}: ")" CONFIRM_UPGRADE_REMOVE < /dev/tty
  if [[ ! "${CONFIRM_UPGRADE_REMOVE}" =~ ^[Rr]$ ]]; then
      read -p "$(echo -e "Proceed with ${BOLD}ALL the existing${NC} values? ${BOLD}${ITALIC}${YELLOW}[${GREEN}y${YELLOW}/${RED}N${YELLOW}]${NC}: ")" CONFIRM_PROCEED < /dev/tty
      if [[ ! "${CONFIRM_PROCEED}" =~ ^[Yy]$ ]]; then
        read -p "$(echo -e "Provide ${BOLD}New${NC} values? ${BOLD}${ITALIC}${YELLOW}[${GREEN}y${YELLOW}/${RED}N${YELLOW}]${NC}: ")" CONFIRM_PROVIDE < /dev/tty
        if [[ ! "${CONFIRM_PROVIDE}" =~ ^[Yy]$ ]]; then
          echo -e "${RED}Operation cancelled by user.${NC}"
          exit 0 # Exit cleanly if the user doesn't confirm
        else
          echo ""
          echo -e "${YELLOW}🚀 Initiating Newt Service Re-installation...${NC}"

          # Capture default/user provided NEWT ID, SECRET and Pangolin Endpoint
          SITE_ID=$(prompt_with_default "Provide Site ID." "$SITE_ID")
          SITE_SECRET=$(prompt_with_default "Provide Site Secret." "$SITE_SECRET")
          PANGOLIN_ENDPOINT=$(prompt_with_default "Provide Pangolin Endpoint." "$PANGOLIN_ENDPOINT")

          read -p "$(echo -e "Enable ${BOLD}Docker Socket${NC} Access? ${BOLD}${ITALIC}${YELLOW}[${GREEN}y${YELLOW}/${RED}N${YELLOW}]${NC}: ")" DOCKER_SOCKET < /dev/tty
          if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]]; then
              if [[ -z "${DOCKER_SOCKET_PATH}" ]]; then
                  DOCKER_SOCKET_PATH=$(prompt_with_default "Provide Docker Socket Path." "/var/run/docker.sock")
              else
                  DOCKER_SOCKET_PATH=$(prompt_with_default "Provide Docker Socket Path." "$DOCKER_SOCKET_PATH")
              fi
          fi
          
          read -p "$(echo -e "Enable ${BOLD}Pangolin/OLM Clients${NC} Access? ${BOLD}${ITALIC}${YELLOW}[${GREEN}y${YELLOW}/${RED}N${YELLOW}]${NC}: ")" NEWT_CLIENTS < /dev/tty
          read -p "$(echo -e "Enable ${BOLD}Native${NC} Mode? ${BOLD}${ITALIC}${YELLOW}[${GREEN}y${YELLOW}/${RED}N${YELLOW}]${NC}: ")" NEWT_NATIVE < /dev/tty
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
      echo -e "${BOLD}${YELLOW}Removed Newt Service user, group and service. 👋 Goodbye!${NC}"
      exit 0
  fi
  echo ""
# --- or Capture User Input for First Time Service Installation ---
else
  echo ""
  echo -e "${YELLOW}🚀 Initiating Newt Service Installation...${NC}"
  read -p "$(echo -e "Provide ${BOLD}Site ID${NC}: ")" SITE_ID < /dev/tty
  read -p "$(echo -e "Provide ${BOLD}Site Secret${NC}: ")" SITE_SECRET < /dev/tty
  read -p "$(echo -e "Provide ${BOLD}Pangolin Endpoint${NC} (ex. ${ITALIC}https://pangolin.yourdomain.com${NC}): ")" PANGOLIN_ENDPOINT < /dev/tty
  read -p "$(echo -e "Enable ${BOLD}Docker Socket${NC} Access ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" DOCKER_SOCKET < /dev/tty
  if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "Provide ${BOLD}Docker Socket Path${NC} (ex. ${ITALIC}/var/run/docker.sock${NC}): ")" DOCKER_SOCKET_PATH < /dev/tty
  fi
  read -p "$(echo -e "Enable ${BOLD}Pangolin/OLM Clients${NC} Access? ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" NEWT_CLIENTS < /dev/tty
  read -p "$(echo -e "Enable ${BOLD}Native${NC} Mode ${BOLD}${YELLOW}${ITALIC}(y/N)${NC}: ")" NEWT_NATIVE < /dev/tty
  echo ""
fi

# --- Newt Binary Download and Update Section ---
echo ""
echo -e "${BOLD}${YELLOW}🔍 Checking for the latest Newt binary...${NC}"

# Detect system architecture
ARCH=$(dpkg --print-architecture) # Common command on Debian/Ubuntu-based systems

case "$ARCH" in
  amd64)
    NEWT_ARCH="amd64"
    ;;
  arm64)
    NEWT_ARCH="arm64"
    ;;
  arm32)
    NEWT_ARCH="arm32"
    ;;
  arm32v6)
    NEWT_ARCH="arm32v6"
    ;;
  *)
    echo -e "${BOLD}${RED}❌ Error: Unsupported architecture: $ARCH${NC}"
    echo -e "${RED}This script supports ONLY amd64, arm64, arm32 and arm32v6.${NC}"
    exit 1
    ;;
esac
echo ""
echo -e "🔍 Detected architecture: ${YELLOW}$ARCH ($NEWT_ARCH)${NC}"

# Generate Release/Download URL based on the 'latest' tag
RELEASE_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_TAG}/newt_linux_${NEWT_ARCH}"
if [ -z "${RELEASE_URL}" ]; then
    echo -e "${RED}❌ Error: Could not fetch Newt release url from GitHub.${NC}"
    exit 1 # Exit if we can't get the latest version tag
else
    echo -e "🔍 New release url found: ${YELLOW}$RELEASE_URL${NC}"
    # Construct the download URL using the found tag name and detected architecture
    #DOWNLOAD_URL="https://github.com/fosrl/newt/releases/download/${LATEST_RELEASE_URL}/newt_linux_${NEWT_ARCH}"
    DOWNLOAD_URL="${RELEASE_URL}"
    # Check if the binary already exists and is the latest version (optional but good practice)
    # This part is complex without knowing the installed version, so we'll just download and replace
    # if [ -f "$NEWT_BIN_PATH" ] && "$NEWT_BIN_PATH" --version 2>/dev/null | grep -q "$LATEST_RELEASE_URL"; then
    #   echo "Newt binary is already the latest version ($LATEST_RELEASE_URL). Skipping download."
    # else
    echo -e "⬇ Attempting to download ${YELLOW}Newt binary for ${ARCH}${NC}..."
    if ! wget -q -O /tmp/newt_temp -L "$DOWNLOAD_URL"; then
      echo -e "${RED}❌ Error: Failed to download Newt binary from $DOWNLOAD_URL.${NC}"
      echo -e "${YELLOW}Please check the URL and your network connection.${NC}"
      exit 1
    fi
    echo -e "=== ${GREEN}✅ Download Complete${NC} ==="
    echo ""
    echo -e "Installing ${GREEN}Newt binary${NC} to 📂 ${GREEN}$NEWT_BIN_PATH${NC}"
    chmod +x /tmp/newt_temp
    mv /tmp/newt_temp "$NEWT_BIN_PATH"
    echo -e "✅ ${GREEN}Newt binary${NC} installed successfully."
    echo ""
fi

# --- End of Newt Binary Section ---

# Initialize ExecStartValue
ExecStartValue="$NEWT_BIN_PATH --id ${SITE_ID} --secret ${SITE_SECRET} --endpoint ${PANGOLIN_ENDPOINT} --health-file /tmp/newt-healthy"

# Conditionally add --disable-clients, --native or --docker-socket flags - ONLY for Upgrade Choice
if [[ "${NEWT_CLIENTS}" =~ ^[Nn]$ ]]; then
    ExecStartValue+=" --disable-clients true"
fi
if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]]; then
    DOCKER_SOCKET_PATH="${DOCKER_SOCKET_PATH//[[:space:]]/}"
    : "${DOCKER_SOCKET_PATH:=/var/run/docker.sock}"
    ExecStartValue+=" --docker-socket ${DOCKER_SOCKET_PATH}"
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
    # Create the directory for the newt Service User and group if they don't exist
    getent group newt >/dev/null || groupadd newt
    
    if [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]] && getent group docker >/dev/null; then
        if ! getent passwd newt >/dev/null; then
            useradd -r -g newt -G docker -s /usr/sbin/nologin -c "Newt Service User" newt
            echo -e "🦰 ${GREEN}Newt${NC} Service User has been ${BOLD}created and added${NC} to the standard ${GREEN}docker${NC} group!"
        else
            usermod -aG docker newt
            echo -e "🦰 ${GREEN}Newt${NC} Service User ${BOLD}already exists and has been added${NC} to the standard ${GREEN}docker${NC} group!"
        fi
    elif [[ "${DOCKER_SOCKET}" =~ ^[Yy]$ ]] && ! getent group docker >/dev/null; then
        if ! getent passwd newt >/dev/null; then
            useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
            echo -e "Although standard ${RED}docker${NC} group not found, 🦰 ${GREEN}Newt${NC} Service User is ${BOLD}created${NC}. 💡 ${BOLD}${RED}REMEMBER${NC} to add it to your ${BOLD}${YELLOW}custom docker${NC} group!"
        else
            echo -e "Although standard ${RED}docker${NC} group not found, 🦰 ${GREEN}Newt${NC} Service User ${BOLD}already exists${NC}. 💡 ${BOLD}${RED}REMEMBER${NC} to add it to your ${BOLD}${YELLOW}custom docker${NC} group!"
        fi
    elif getent passwd newt >/dev/null && id -nG "newt" | grep -qw "docker"; then
        gpasswd -d newt docker
        echo -e "🦰 ${YELLOW}${BOLD}Removed${NC} ${YELLOW}existing Newt Service User from standard docker group!${NC}"
    else
        # This block handles all other cases, including when the user is created for the first time
        if ! getent passwd newt >/dev/null; then
            useradd -r -g newt -s /usr/sbin/nologin -c "Newt Service User" newt
            echo -e "🦰 A regular ${GREEN}Newt${NC} Service User has been ${BOLD}created${NC}!"
        else
            echo -e "🦰 A regular ${GREEN}Newt${NC} Service User ${BOLD}already exists${NC}!"
        fi
    fi
    mkdir -p "${NEWT_LIB_PATH}"
    chown newt:newt "${NEWT_LIB_PATH}"
fi

# Stop the Service, if it exists
if [[ -f "${SERVICE_FILE}" ]]; then
    systemctl stop $SERVICE_NAME
fi
# Write the content to the service file
echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null
echo -e "🗒️ ===> Systemd service file (re)created at ${BOLD}${GREEN}$SERVICE_FILE${NC} with provided NEWT VPN Client details. <==="
echo ""
echo -e "${BOLD}${YELLOW}⚙️ Enabling/Starting the service after daemon-reload...${NC}"
echo ""
echo -e "${BOLD}${YELLOW}💡 Press 'q' to exit!${NC}"
echo ""
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME
systemctl status $SERVICE_NAME
echo ""
echo -e "${BOLD}===========================================${NC}"
echo -e "${BOLD}${GREEN}Newt Client Service installed. 👋 Goodbye!${NC}"
echo -e "${BOLD}===========================================${NC}"
echo ""
exit 0
