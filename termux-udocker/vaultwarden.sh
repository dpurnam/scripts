#!/data/data/com.termux/files/usr/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/source.env"

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE_NAME="vaultwarden"
CONTAINER_NAME="vaultwarden-server"

case $PORT in
    ''|*[!0-9]*) PORT=2080;;
    *) [ $PORT -gt 1023 ] && [ $PORT -lt 65536 ] || PORT=2080;;
esac

udocker_check
udocker_prune
udocker_create "$CONTAINER_NAME" "$IMAGE_NAME"

DATA_DIR="$(pwd)/data-$CONTAINER_NAME"

# --- Load env vars from ${CONTAINER_NAME}.env ---
ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/${CONTAINER_NAME}.env"
ENV_ARGS=""

if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
      ENV_ARGS+=" -e $line"
    fi
  done < "$ENV_FILE"
fi

# --- Load volume/mounts from ${CONTAINER_NAME}.vol ---
VOL_FILE="$(dirname "${BASH_SOURCE[0]}")/${CONTAINER_NAME}.vol"
VOL_ARGS=""

if [ -f "$VOL_FILE" ]; then
  while IFS= read -r line; do
    # Ignore comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    # Only include lines with host:container mapping
    if [[ "$line" =~ ^[^:]+:[^:]+$ ]]; then
      VOL_ARGS+=" -v $line"
    fi
  done < "$VOL_FILE"
fi

if [ -n "$1" ]; then
  unset cmd
  cmd="$*"
  udocker_run --entrypoint "bash -c" $ENV_ARGS $VOL_ARGS -p "$PORT:80" "$CONTAINER_NAME" "$cmd"
else
  udocker_run --entrypoint "bash -c" $ENV_ARGS $VOL_ARGS -p "$PORT:80" -e _PORT="$PORT" "$CONTAINER_NAME" ' \
      echo -e "127.0.0.1   localhost.localdomain localhost\n::1         localhost.localdomain localhost ip6-localhost ip6-loopback\nfe00::0     ip6-localnet\nff00::0     ip6-mcastprefix\nff02::1     ip6-allnodes\nff02::2     ip6-allrouters" >/etc/hosts; \
      sed -i -E "s/^Listen .*/Listen $_PORT/" /etc/apache2/ports.conf &>/dev/null; \
      sed -i "s/<VirtualHost .*/<VirtualHost *:$_PORT>/" /etc/apache2/sites-enabled/000-default.conf &>/dev/null; \
      mkdir -p /var/log/apache2; \
      rm -f /var/log/apache2/*.{pid,log} /var/run/apache2/*.pid; \
      touch /var/log/apache2/{access,error,other_vhosts_access,daemon}.log; \
      tail -F /var/log/apache2/error.log 1>&2 & \
      tail -qF /var/log/apache2/{access,other_vhosts_access,daemon}.log & \
      _PIDFILE=\"$(mktemp)\"; \
      start-stop-daemon -mp \"$_PIDFILE\" -bSa \"$(command -v bash)\" -- -c \"exec /entrypoint.sh apache2-foreground >/var/log/apache2/daemon.log 2>&1\" && \
      while start-stop-daemon -Tp \"$_PIDFILE\"; do sleep 10; done
  '
fi

exit $?
