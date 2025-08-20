#!/bin/bash
# WakeMyPotata emergency RAID/system safe shutdown
# For battery-powered devices only
# https://github.com/dpurnam/scripts/tree/main/WakeMyPotata

set -e

REPO_URL="https://raw.githubusercontent.com/dpurnam/scripts/main/WakeMyPotata"
BIN_DIR="/usr/local/sbin"
SYSTEMD_DIR="/etc/systemd/system"

echo "  Welcome to the WakeMyPotata installer!"
echo "  Enter seconds to wake up after a blackout,"
echo "  leave empty to use the default 600 seconds:"
read -p "  > " timeout

if [[ -z "$timeout" ]]; then
    timeout=600
fi
if [[ ! "$timeout" =~ ^[0-9]+$ ]]; then
    echo "  Invalid input, please enter a positive integer! Aborting..."
    exit 1
fi

# Check for upower and install if missing
if ! command -v upower &>/dev/null; then
    echo "  upower not found. Attempting to install (requires sudo/root)..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y upower
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y upower
    elif command -v yum &>/dev/null; then
        sudo yum install -y upower
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy upower
    else
        echo "  Could not detect package manager. Please install upower manually for battery support."
        exit 1
    fi
fi

# ABORT install if no battery detected
BAT_PATH=$(upower -e 2>/dev/null | grep -m1 BAT || true)
if [ -z "$BAT_PATH" ]; then
    echo "  ERROR: No battery detected. WakeMyPotata only works on devices with a battery. Aborting install."
    exit 1
fi

echo "  Downloading and installing WakeMyPotata files..."

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

echo "  WakeMyPotata installed successfully!"
echo "  Use 'sudo wmp help' for info on user commands."
