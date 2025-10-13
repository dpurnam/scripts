# Scripts
- Termux Udocker's **[Vaultwarden](https://github.com/dpurnam/scripts/tree/main/termux-udocker)** (newly added)
  - Script for `Single Container` docker compose files to be used by [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
  - [Sample Script for Vaultwarden](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden.sh) along with its [docker compose file](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden-docker-compose.yml) available
  - Customize/rewrite the script for any other services you'd like to run
  - Automate service start using `termux-boot` and `termux-services` pkgs at Termux App launch
  - Tested on a Non-Rooted Android phone running Termux from F-Droid

-----
- Pangolin's **Newt VPN Client [Service Manager](https://github.com/dpurnam/scripts/tree/main/newt)**
  - User-friendly prompt based bash script, primarily for debian based Linux hosts
  - Freshly Install Newt VPN Client Systemd Service
  - Update Newt VPN Client Binary
  - Remove Newt Systemd Service
  - Supports OLM Clients and Native Mode

-----
- Stalwart Mailserver [Scripts](https://github.com/dpurnam/scripts/tree/main/stalwart)
  - **[Cloudflare TLSA Record Updater](https://github.com/dpurnam/scripts/blob/main/stalwart/cloudflare-tlsa-record-updater.sh)**
    -  Set up or Update a TLSA record (used for `DANE` feature of Stalwart) on an associated Cloudflare Account
  - **[Full Backup/Restore Manager](https://github.com/dpurnam/scripts/tree/main/stalwart)** (newly added)
    -  Complete backup or restore of PostgresSQL DB and all (or pre-defined list of) Accounts - `Individual type Principals`
    -  Compression and Encryption before/after syncing with desired Storage Provider via `rclone`

-----
- Device Availability Manager - **[WakeMyPotata](https://github.com/dpurnam/scripts/tree/main/WakeMyPotata)**
  - Automatically boot up a device after AC power outage using `rtcwakeup` tool. Now supports both battery-powered as well as battery-less devices!

-----
