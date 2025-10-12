# Vaultwarden Udocker Installer
- Script for `Single Container` docker compose files to be used by [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
- [Sample Script for Vaultwarden](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden.sh) along with its [docker compose file](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden-docker-compose.yml) available
- Customize the script for any other services you'd like to run
- Tested on a Non-Rooted Android phone running Termux from F-Droid
# Usage (in Termux Terminal)
1. Git clone [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
2. Prepare Service `(Vaultwarden)` Directory structure `mkdir -p $HOME/Termux-Udocker/vaultwarden/data`
3. Download `vaultwarden.sh` to `$HOME/Termux-Udocker` and make it executable `chmod +x`
4. Download `vaultwarden-docker-compose.yml` to `$HOME/Termux-Udocker/vaultwarden` and rename it to `mv vaultwarden-docker-compose.yml docker-compose.yml`
5. Run `cd $HOME/Termux-Udocker; ./vaultwarden.sh`

OR

1. Automatically create the directory structure in present working directory `(typically $HOME/Termux-Udocker)` and download the sample docker compose file 
```
cd $HOME/Termux-Udocker
curl -sL "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden.sh" | bash
```
2. Download it in present working directory `(typically $HOME/Termux-Udocker)` for further customization (for example setup a terux-service for vaultwarden using termux-services package)
```
cd $HOME/Termux-Udocker
curl -sL "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden.sh" -o vaultwarden.sh
chmod +x vaultwarden.sh
```
2. Modify the Docker Compose file with valid information and re-run the script `./vaultawarden.sh`
