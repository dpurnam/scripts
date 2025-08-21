#!/bin/bash
# WakeMyPotata emergency RAID/system safe shutdown
# For battery-powered devices only

set -e

REPO_URL="https://raw.githubusercontent.com/dpurnam/scripts/main/WakeMyPotata"
BIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
BOLD='\e[1m'
NC='\e[0m' # No Color

echo ""
echo -e "${BOLD}===============================${NC}"
echo -e "${GREEN}${BOLD}WakeMyPotata${NC} ${GREEN}Service Installer!${NC}"
echo -e "${BOLD}===============================${NC}"
echo ""

# User input to capture Timeout
read -p "$(echo -e "Enter amount of ${BOLD}time (in seconds)${NC} to wake up the device ${BOLD}after a blackout${NC}. ${YELLOW}or leave empty to use the default 600 seconds!${NC} : ")" timeout < /dev/tty
# Set/Verify Timeout Value
if [[ -z "$timeout" ]]; then
    timeout=600
fi
if [[ ! "$timeout" =~ ^[0-9]+$ ]]; then
    echo -e "${BOLD}${RED}Invalid input, please enter a positive integer! Aborting...${NC}"
    exit 1
    echo ""
fi
echo ""

# User input to confirm Battery-powered device or not
read -p "$(echo -e "Is this device powered by a ${BOLD}bulit-in battery${NC}? ${YELLOW}${BOLD}(y/N)${NC}: ")" confirm_battery_powered_device < /dev/tty
echo ""
if [[ "${confirm_battery_powered_device}" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "${YELLOW}Enter battery level threshold (between 10-50%) to wake up the device ${BOLD}after a blackout${NC}. ${YELLOW}or leave empty to use the default value of 10%!${NC} : ")" threshold < /dev/tty
    echo -e "Please Note: This setting will be ignored if upower tool does ${BOLD}not detect a built-in battery${NC}!"
    echo ""
    # Set/Verify Threshold Value
    if [[ -z "$threshold" ]]; then
        threshold=10
    fi
    if [[ ! "$threshold" =~ ^[0-9]+$ ]] || (( threshold < 10 || threshold > 50 )); then
        echo -e "${RED}Invalid input, please enter a positive integer ${BOLD}between 10 and 50${NC}${RED}! Aborting...${NC}"
        exit 1
        echo ""
    fi
fi
echo ""

BATTERY_THRESHOLD=$threshold

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

# Identify built-in battery using upower tool
BAT_PATH=$(upower -e 2>/dev/null | grep -m1 BAT || true)
if [ -z "$BAT_PATH" ]; then
    echo -e "${RED}upower tool ${BOLD}could not detect${NC} ${RED}a built-in battery. ${BOLD}Disabling${NC} ${RED}Threshold Feature!${NC}"
    threshold_feature=0
else
    echo -e "${GREEN}upower tool ${BOLD}successfully detected${NC} ${GREEN}a built-in battery. ${BOLD}Enabling${NC} ${GREEN}Threshold Feature!${NC}"
    threshold_feature=1
fi

# Download components from GITHUB viz. wmp, wmp-run, wmp.service and wmp.timer
echo ""
echo -e "${YELLOW}Downloading and installing WakeMyPotata components...${NC}"
echo ""
# Download systemd units (with error handling)
curl -sSL "$REPO_URL/src/wmp.timer" -o "$SYSTEMD_DIR/wmp.timer" || { echo "Failed to download wmp.timer"; exit 1; }
curl -sSL "$REPO_URL/src/wmp.service" -o "$SYSTEMD_DIR/wmp.service" || { echo "Failed to download wmp.service"; exit 1; }
chmod 644 "$SYSTEMD_DIR/wmp.timer" "$SYSTEMD_DIR/wmp.service"

# Download main scripts
curl -sSL "$REPO_URL/src/wmp" -o "$BIN_DIR/wmp" || { echo "Failed to download wmp"; exit 1; }
curl -sSL "$REPO_URL/src/wmp-run" -o "$BIN_DIR/wmp-run" || { echo "Failed to download wmp-run"; exit 1; }
chmod 744 "$BIN_DIR/wmp" "$BIN_DIR/wmp-run"

# Patch Service file's ExecStart to pass args
if [[ $threshold_feature -eq 1 ]]
    sed -i "s|^ExecStart=.*|ExecStart=$BIN_DIR/wmp-run --timeout $timeout --threshold $BATTERY_THRESHOLD|" "$SYSTEMD_DIR/wmp.service"
elif [[ $threshold_feature -eq 0 ]]
    sed -i "s|^ExecStart=.*|ExecStart=$BIN_DIR/wmp-run --timeout $timeout|" "$SYSTEMD_DIR/wmp.service"
fi

systemctl daemon-reload
systemctl enable wmp.timer
systemctl start wmp.timer
echo ""
echo -e "${GREEN}${BOLD}WakeMyPotata Service & Timer${NC} ${GREEN}installed successfully!${NC}"
echo -e "${YELLOW}Use '${BOLD}sudo wmp help${NC}' ${YELLOW}for info on user commands.${NC}"
echo ""
