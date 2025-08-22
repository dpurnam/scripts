WakeMyPotata!
=============

**WakeMyPotata** is a Linux tool designed to protect your data and RAID systems from sudden AC power loss on devices with a battery (like laptops or battery-backed servers). It monitors your device battery and AC power status, and if AC power is lost and the device battery drops below a set threshold, it safely shuts down your system and schedules an automatic restart after a specified time.

**Additionally, it now supports** devices without a built-in battery but with limited functionality viz. - schedule an automatic power-up after a specified timeout period, when an AC power outage abruptly shuts down the device

**Inspired by [WakeMyPotato](https://github.com/pablogila/WakeMyPotato)**

## Who Should Use It?
- Anyone who wants to automatically power-up their device, after power outages.
- Laptop or battery-backed server users who want automated, safe shutdown and power-up after power outages.
- Anyone running RAID arrays or important file systems on systems with a battery that need extra protection from power events.

## Why Use WakeMyPotata?

- **Protects your RAID and data**

  Ensures RAID arrays and file systems are *safely unmounted before the system shuts down, reducing risk of data loss or corruption.
- **Automatic recovery**

  Schedules your device to wake up and restart after power returns, minimizing downtime.
- **Customizable**

  Set your preferred battery threshold and wake timeout to match your needs.
- **Seamless integration**

  Installs as a systemd service and timer, working quietly in the background.
- **Easy control**

  Includes a command-line interface for checking *battery status, setting configuration, viewing logs, and managing the service.

( * `works only on devices with built-in battery such as laptops` )

## Pre-requisites
- A functional/healthy **CMOS** Battery
- A functional/healthy **Device** Battery, in case 'safe shutdown of RAID systems' is required
- **RTC Wake** Feature available on the device

  To check, run this command, which should instantly poweroff the device and boot it up after **2 minutes** (time specified in seconds)
    ```shell
    sudo rtcwake --list-modes ; sleep 10
    sudo rtcwake -m off -s 120
    ```

## Installation / Removal

To install, just run:

```shell
curl -sSL https://raw.githubusercontent.com/dpurnam/scripts/main/WakeMyPotata/install.sh | sudo bash
```

To remove, just run:

```shell
sudo wmp uninstall
```

## Usage
The service includes the `wmp` utility to perform several tasks.
To check all available commands, use `sudo wmp help`.

| Command | Description |
| ------- | ----------- |
| `sudo wmp help`                    | Show all available commands |
| `sudo wmp version`                 | Print the software version |
| `sudo wmp status`                  | Check the service status |
| `sudo wmp log`                     | View recent warning logs |
| `sudo wmp battery`*                | View recent warning logs |
| `sudo wmp threshold`*              | Show battery level threshold in % |
| `sudo wmp threshold set <percent>`*| Set battery level threshold in % (10-50) |
| `sudo wmp timeout`                 | Show timeout value (seconds) |
| `sudo wmp timeout set <seconds>`   | Set new timeout value |
| `sudo wmp run <seconds>`           | Run a manual check |
| `sudo wmp stop`                    | Stop the service |
| `sudo wmp start`                   | Start the service |
| `sudo wmp uninstall`               | Uninstall the service |
( * `works only on devices with built-in battery such as laptops` )

## Components

- [wmp-run](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp-run) : The Core Intelligence.

  Handles low battery scenario, only triggers shutdown when necessary, and schedules rtcwake for AC restoration.
- [wmp](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp) : The Control Script.

  Robust CLI for manual intervention.
- [wmp.service](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.service) : The Systemd Service Unit.

  Systemd Service Unit quitely running in the background.
- [wmp.timer](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.timer) : The Systemd Service Timer.

  Service Timer quitely supporting the Systemd Service Unit.

## Limitations
- Requires Linux with systemd, `upower`, and RTC wake support.
