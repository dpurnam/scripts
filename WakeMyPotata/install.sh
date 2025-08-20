#!/bin/bash
# WakeMyPotata emergency RAID/system safe shutdown
# For battery-powered devices only
# https://github.com/dpurnam/scripts/tree/main/WakeMyPotata

set -e

REPO_URL="https://raw.githubusercontent.com/dpurnam/scripts/main/WakeMyPotata"
BIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"

# ANSI color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
BOLD='\e[1m'
ITALIC='\e[3m'
NC='\e[0m' # No Color

echo -e "${BOLD}======================================${NC}"
echo -e "${GREEN}Welcome to the ${BOLD}WakeMyPotata${NC} ${GREEN}installer!${NC}"
echo -e "${BOLD}======================================${NC}"
echo ""
echo -e "${YELLOW}Enter amount of time (in seconds) to wake up the device ${BOLD}after a blackout${NC} ${YELLOW}or leave empty to use the default 600 seconds!${NC}"
read -p "  ==> " timeout < /dev/tty
echo ""

if [[ -z "$timeout" ]]; then
    timeout=600
fi
if [[ ! "$timeout" =~ ^[0-9]+$ ]]; then
    echo -e "${BOLD}${RED}Invalid input, please enter a positive integer! Aborting...${NC}"
    exit 1
fi

# Check for upower and install if missing
if ! command -v upower &>/dev/null; then
    echo -e "${YELLOW}${BOLD}upower${NC} ${YELLOW}not found. Attempting to install (requires sudo/root)...${NC}"
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y upower
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y upower
    elif command -v yum &>/dev/null; then
        sudo yum install -y upower
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy upower
    else
        echo -e "${RED}Could not detect package manager. Please install ${BOLD}upower${NC} ${RED}manually for battery support.${NC}"
        exit 1
    fi
fi

# ABORT install if no battery detected
BAT_PATH=$(upower -e 2>/dev/null | grep -m1 BAT || true)
if [ -z "$BAT_PATH" ]; then
    echo -e "${RED}${BOLD}ERROR:${NC} ${RED}No battery detected. ${BOLD}WakeMyPotata${NC} ${RED}only works on devices with a battery. Aborting install.${NC}"
    exit 1
fi

echo -e "${YELLOW}Downloading and installing WakeMyPotata files...${NC}"

# Download and install systemd units
curl -sSL "$REPO_URL/src/wmp.timer" -o "$SYSTEMD_DIR/wmp.timer"
curl -sSL "$REPO_URL/src/wmp.service" -o "$SYSTEMD_DIR/wmp.service"
chmod 644 "$SYSTEMD_DIR/wmp.timer" "$SYSTEMD_DIR/wmp.service"

# Download and install main scripts
curl -sSL "$REPO_URL/src/wmp" -o "$BIN_DIR/wmp"
curl -sSL "$REPO_URL/src/wmp-run" -o "$BIN_DIR/wmp-run"
chmod 744 "$BIN_DIR/wmp" "$BIN_DIR/wmp-run"

# Patch ExecStart for timeout
sed -i "s|^ExecStart=.*|ExecStart=$BIN_DIR/wmp-run $timeout|" "$SYSTEMD_DIR/wmp.service"

systemctl daemon-reload
systemctl enable wmp.timer
systemctl start wmp.timer
echo ""
echo -e "${GREEN}${BOLD}WakeMyPotata${NC} ${GREEN}installed successfully!${NC}"
echo -e "${YELLOW}Use '${BOLD}${YELLOW}sudo wmp help${NC}' ${YELLOW}for info on user commands.${NC}"
