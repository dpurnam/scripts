# Vaultwarden Udocker Installer
- Script for `Single Container` docker compose files to be used by [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
- Sample Script for Vaultwarden along with its docker compose file available
- Customize the script for any other services you'd like to run
- Tested on a Non-Rooted Android phone running Termux from F-Droid
# Usage (in Termux Terminal)
1. Prepare Directory structure `$HOME/vaultwarden/data`
2. Download vaultwarden.sh to `$HOME/vaultwarden` and make it executable `chmod +x`
3. Download `vaultwarden-docker-compose.yml` to `$HOME/vaultwarden` and rename it to `docker-compose.yml`
4. Run `cd $HOME/vaultwarden; ./vaultwarden.sh`

OR

1. Run the following to automatically create the directory structure in present working directory and download the sample docker compose file
```
curl -sL "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden.sh" -o vaultwarden.sh
chmod +x vaultwarden.sh
```
2. Modify the Docker Compose file with valid information and re-run the script `./vaultawarden.sh`
