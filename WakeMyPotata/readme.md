WakeMyPotata
=============

WakeMyPotata (WMP) is a simple and last-resort systemd Linux service to keep your old potata laptop(s) alive and running in the event of a power failure.

Inspired by [WakeMyPotato](https://github.com/pablogila/WakeMyPotato)


## Installation / Removal

To install, just run:

```shell
curl -sSL https://raw.githubusercontent.com/dpurnam/scripts/main/WakeMyPotata/install.sh | sudo bash
```

To remove, just run:

```shell
sudo wmp uninstall
```

## [Usage](https://github.com/pablogila/WakeMyPotato/tree/main#usage)
The service includes the `wmp` utility to perform several tasks.
To check all available commands, use `sudo wmp help`.

| Command | Description |
| ------- | ----------- |
| `sudo wmp help`          | Show all available commands |
| `sudo wmp version`       | Print the software version |
| `sudo wmp status`        | Check the service status |
| `sudo wmp log`           | View recent warning logs |
| `sudo wmp set <seconds>` | Set new configuration |
| `sudo wmp run <seconds>` | Run a manual check |
| `sudo wmp stop`          | Stop the service |
| `sudo wmp start`         | Start the service |
| `sudo wmp uninstall`     | Uninstall the service |

## Components

- [wmp-run](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp-run) : The Core Intelligence.

  Handles both battery-present and battery-absent scenarios, only triggers shutdown when necessary, and schedules rtcwake for AC restoration.
- [wmp](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp) : The Control Script.

  Adds a battery command for user status, more robust CLI.
- [wmp.service](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.service) : The Systemd Service Unit File.

  No major changes, but fully compatible with revised logic.
- [wmp.timer](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.timer) : The Systemd Service Timer File.

  No major changes, but fully compatible with revised logic.

## Scenarios Supported
Scenario 1:
- Battery exists
- rtcwake/shutdown is only triggered if BOTH AC power is lost AND battery ≤ 10%
- If AC returns before battery hits 10%, no shutdown

Scenario 2:
- No battery present
- On AC loss, just trigger rtcwake in 'no' mode (wake up only, no shutdown)
- If AC returns, no shutdown
