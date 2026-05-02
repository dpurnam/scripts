Vaultwarden Rsync to Cloudflare R2 (Shell Script) : VWRsync2R2
=================================================================

**VWRsync2R2** is a Linux tool designed to backup your backup your Vaultwarden Docker Container to any S3 compatible object storage. (We're using Cloudflare R2, here)

## Who Should Use It?
- Anyone who wants to automatically backup their vaultwarden data to cloud storage.

## Why Use WakeMyPotata?

- **Auto Backup your Vaultwarden data on desired cron schedule**

  Schedule a custom cron to run the script on the same server.
- **Manual Restore**

  Manually restore from the S3 cloud storage to any host you desire
- **Customizable**

  Set your preferred S3 cloud storage, change appropriate local directory locations et al and you've your own backup/restore mechanism for that crucial Vaultwarden Data.
- **Seamless usage**

  Relies on docker containers viz. rclone and minimal local packages such as jq, gpg etc.
- **Easy control**

  Includes a command-line options to either upload or download the data.


## Pre-requisites
- A functional/healthy **Vaultwarden** docker container
- Local gpg package for encryption/decryption
- Properly configure supplementary rclone config file `(rclone.conf)` in the same directory as this script

## Usage
Two simple options to perform backup/restore tasks.

| Command | Description |
| ------- | ----------- |
| `sudo r2-sync-armvps.sh -u -p <passkey>`                    | Upload to S3 storage using provided encryption passkey |
| `sudo r2-sync-armvps.sh -d -p <passkey>`                    | Download from S3 storage using provided decryption passkey (must be same as the one used for encryption) |

