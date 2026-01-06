Stalwart Backup/Restore Manager (swmanage)
==========================================

**swmanage** is a Linux bash script/tool designed to backup/restore your Stalwart Accounts and PostgresSQL DB data.

## Who's it for?
- Anyone who wants to automatically backup or restore their Stalwart Accounts and the PostgresSQL DB

## Why swmanage?

- Ready to use yet customizabale - Bash script with its config files
- Supports storage to any S3 compatible service synced up/down via `rclone`
- Local Encryption/Decryption with your passphrase
- Local Compression/Decompression before/after upload/download

## Pre-requisites
- A functional/healthy **Stalwart Mail Server** docker container (and its JMAP/WebAdmin access URL) only upto v0.14.x
- A functional/healthy **PostgresSQL DB** running on the host and configured as backed store in Stalwart

## Usage
1. Download all three files to the Stalwart Top Level Directory on the host.
2. This should be the same directory that you've mapped to `/opt/stalwart` in its docker container.
3. Populate both the config files with valid information

To check all available commands, use `./swmanage.sh ?`.

| Arguments | Description |
| ------- | ----------- |
| `-c`*   | Stalwart Admin user password |
| `-p`*   | Your Encryption/Decryption Passphrase |
| `-m`    | Define script mode viz. `backup` or `restore`.<br>If unused, defaults to `backup` mode |
| `-k`    | If used, keeps the temporary .gzip files for quick local access.<br>If unused, defaults to deleting the temporary .gzip files after the script completes |
| `-z`    | If used, allows to work on custom list of DOMAINS/ACCOUNTS (info must be provied in the Main config file!)<br>If unused, defaults to working on ALL Individual ACCOUNTS from the server. |

( * - Mandatory)

Example:
```
./swmanage.sh -c stalwart_admin_password -p my_passphrase -m backup
```
## Components

- [swmanage.sh](https://github.com/dpurnam/scripts/blob/main/stalwart/swmanage.sh) : The Core Intelligence.

- [swmanage-rclone.conf](https://github.com/dpurnam/scripts/blob/main/stalwart/swmanage-rclone.conf) : The Rclone Config File (Must be populated with Valid Info)

- [swmanage-config.conf](https://github.com/dpurnam/scripts/blob/main/stalwart/swmanage-config.conf) : The Main Config File (must be populated with valid Info)

## Directory Structure:
 .
<br>│   │<br>
├── **backups** `(automatically created)`
<br>│   │<br>
│   └── **myhostname-local** `(automatically created in backup mode)`
<br>│   │   │<br>
│   │   └── **accounts** `(automatically created in backup mode)`
<br>│   │   │<br>
│   │   └── **db** `(automatically created in backup mode)`
<br>│   │<br>
│   └── **myhostname-remote** `(automatically created in restore mode)`
<br>│   │   │<br>
│   │   └── **accounts** `(automatically created in restored mode)`
<br>│   │   │<br>
│   │   └── **db** `(automatically created in restore mode)`
<br>│<br>
├── _cloudflare-tlsa-updater.sh_ `(Custom User File)`
<br>│<br>
├── data `(Stalwart Data Folder)`
<br>│   │<br>
│   ├── 000008.sst
<br>│   │<br>
│   ├── 000009.sst
<br>│   │<br>
│   ├── 000010.blob
<br>│   │<br>
 │   │...
<br>│   │<br>
│   ├── MANIFEST-000439
<br>│   │<br>
│   ├── OPTIONS-000437
<br>│   │<br>
│   └── OPTIONS-000441
<br>│   │<br>
├── etc `(Stalwart etc Folder)`
<br>│   │<br>
│   └── config.toml
<br>│   │<br>
├── logs `(Stalwart Logs Folder)`
<br>│   │<br>
│   ├── stalwart.log.2025-08-08
<br>│   │<br>
 │   │...
<br>│   │<br>
├── _sieve-scripts_ `(Custom User Folder)`
<br>│   │<br>
│   ├── main
<br>│   │<br>
│   ├── hostmaster-forwarding
<br>│   │<br>
│   └── main-user-filters
<br>│<br>
├── **swmanage-config.conf** `(Main Config File)`
<br>│<br>
├── **swmanage-rclone.conf** `(Rclone Config File)`
<br>│<br>
└── **_swmanage.sh_** `(Main Script File)`


## Other packages/components used/installed/launched automatically
- `jq` package
- `rclone` docker image/container
