# Vaultwarden Udocker Installer
- Script for `Single Container` docker compose files to be used by [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
- [Sample Script for Vaultwarden](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden.sh) along with its [docker compose file](https://github.com/dpurnam/scripts/blob/main/termux-udocker/vaultwarden-docker-compose.yml) available
- Customize/rewrite the script for any other services you'd like to run
- Automate service start using `termux-boot` and `termux-services` pkgs at Termux App launch
- Tested on a Non-Rooted Android phone running Termux from F-Droid
  
# Usage (in Termux Terminal)
1. Git clone [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
2. Prepare Service `(Vaultwarden)` Directory structure `mkdir -p $HOME/Termux-Udocker/vaultwarden/data`
3. Download `vaultwarden.sh` to `$HOME/Termux-Udocker` and make it executable `chmod +x $HOME/Termux-Udocker/vaultwarden.sh`
4. Download/Revise `vaultwarden-docker-compose.yml` and rename/move it to `vaultwarden service directory` : `mv vaultwarden-docker-compose.yml $HOME/Termux-Udocker/vaultwarden/docker-compose.yml`
5. Run `cd $HOME/Termux-Udocker; ./vaultwarden.sh`

OR

1. Git clone [udocker](https://github.com/George-Seven/Termux-Udocker/tree/main)
2. Automatically create the directory structure in present working directory `(typically $HOME/Termux-Udocker)` and download the sample docker compose file 
```
cd $HOME/Termux-Udocker
curl -sL "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden.sh" | bash
```
3. Download it in present working directory `(typically $HOME/Termux-Udocker)` for further customization
```
cd $HOME/Termux-Udocker
curl -sL "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden.sh" -o vaultwarden.sh
chmod +x vaultwarden.sh
```
4. Modify the Docker Compose file with valid information and re-run the script `./vaultawarden.sh`
