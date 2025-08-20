#!/bin/bash
# WakeMyPotata emergency RAID/system safe shutdown
# https://github.com/dpurnam/scripts/tree/main/WakeMyPotata
# Inspired by - https://github.com/pablogila/WakeMyPotato

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
    fi
fi

# Warn user if no battery (informational, does not block install)
BAT_PATH=$(upower -e 2>/dev/null | grep -m1 BAT || true)
if [ -z "$BAT_PATH" ]; then
    echo "  Warning: No battery detected. WakeMyPotata will run in AC-only mode."
fi

# Copy all scripts and units
cp src/wmp.timer src/wmp.service /etc/systemd/system/
chmod 644 /etc/systemd/system/wmp.timer /etc/systemd/system/wmp.service
cp src/wmp src/wmp-run /usr/local/sbin/
chmod 744 /usr/local/sbin/wmp /usr/local/sbin/wmp-run

sed -i "s|^ExecStart=.*|ExecStart=/usr/local/sbin/wmp-run $timeout|" /etc/systemd/system/wmp.service

systemctl daemon-reload
systemctl enable wmp.timer
systemctl start wmp.timer

echo "  WakeMyPotata installed successfully!"
echo "  Use 'sudo wmp help' for info on user commands."
