#!/data/data/com.termux/files/usr/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/source.env"
cd "$(dirname "${BASH_SOURCE[0]}")"
#BASE_DIR="$HOME/Termux-Udocker"
#source "${BASE_DIR}/source.env"

SERVICE="vaultwarden"
SERVICE_DIR="$(pwd)/$SERVICE"
DATA_DIR="$SERVICE_DIR/data"
COMPOSE_FILE="$SERVICE_DIR/docker-compose.yml"

mkdir -p "${SERVICE_DIR}" "${DATA_DIR}"

# Ensure docker compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: $COMPOSE_FILE not found." && echo ""
    echo "INFO: Dowloading a sample now..." && echo ""
    if ! dpkg -s wget &> /dev/null; then
        echo "INFO: wget not found. Installing via pkg..."
        pkg install wget -y
    fi
    wget -qO "${COMPOSE_FILE}" "https://raw.githubusercontent.com/dpurnam/scripts/main/termux-udocker/vaultwarden-docker-compose.yml" && echo "" 
    echo "NOTICE: Modify the sample docker compose file with valid information and re-run this script!" && echo ""
    exit 1
fi

# Check if the 'yq' package is installed using dpkg (which returns 0 if installed)
if ! dpkg -s yq &> /dev/null; then
    echo "INFO: yq not found. Installing via pkg..."
    pkg install yq -y
fi

# Extract container name
CONTAINER_NAME=$(yq e ".services.$SERVICE.container_name" $COMPOSE_FILE)

# -----------------------------------
# --- ARGUMENT PARSING BLOCK ---
if [ "$1" = "-remove" ]; then
    echo "Stopping and removing container: ${CONTAINER_NAME}..."
    # Check if the container exists (optional safety check)
    if udocker ps -a | grep -q "${CONTAINER_NAME}"; then
        udocker rm "${CONTAINER_NAME}"
        echo "Container ${CONTAINER_NAME} removed successfully."
    else
        echo "Container ${CONTAINER_NAME} not found. Nothing to remove."
    fi
    exit 0 # Exit immediately after removal
fi
# -----------------------------------

# Extract image name
IMAGE_NAME=$(yq e ".services.$SERVICE.image" $COMPOSE_FILE)

# Extract port mappings
PORT_ARGS=()
ports=$(yq e ".services.$SERVICE.ports[]" $COMPOSE_FILE)
if [ "$ports" != "null" ]; then
  for port in $(yq e ".services.$SERVICE.ports[]" $COMPOSE_FILE); do
    host_port=$(echo "$port" | cut -d: -f1)
    container_port=$(echo "$port" | cut -d: -f2)
    if [ "$host_port" -lt 1024 ] || [ "$container_port" -lt 1024 ]; then
      echo "INFO: Port mapping for privileged port ($host_port:$container_port) ignored. udocker will remap automatically."
      continue
    fi
    PORT_ARGS+=("-p" "$host_port:$container_port")
  done
  #echo "${PORT_ARGS[@]}" # Uncomment for Debugging/Displaying Ports mapped
fi


# Extract environment variables
ENV_ARGS=()
envs=$(yq e ".services.$SERVICE.environment" $COMPOSE_FILE)
if [ "$envs" != "null" ]; then
  # Map format
  for key in $(yq e ".services.$SERVICE.environment | keys | .[]" $COMPOSE_FILE); do
    value=$(yq e ".services.$SERVICE.environment.\"$key\"" $COMPOSE_FILE)
    ENV_ARGS+=("-e" "$key=$value")
  done
  # Array format
  for env in $(yq e ".services.$SERVICE.environment[]" $COMPOSE_FILE 2>/dev/null); do
    [[ "$env" =~ "=" ]] && ENV_ARGS+=("-e" "$env")
  done
  #echo "${ENV_ARGS[@]}" # Uncomment for Debugging/Diplaying all the Environment Variables used
fi


# Extract volume mappings
VOL_ARGS=""
vols=$(yq e ".services.$SERVICE.volumes[]" $COMPOSE_FILE)
if [ "$vols" != "null" ]; then
  for vol in $(yq e ".services.$SERVICE.volumes[]" $COMPOSE_FILE); do
    vol_expanded=$(eval echo "$vol")
    VOL_ARGS+=" -v $vol_expanded"
  done
  #echo "${VOL_ARGS[@]}" # Uncomment for Debugging/Diplaying all the Volumes mapped
fi

# Parse Compose file for Entrypoint and Command, if any
ENTRYPOINT=$(yq e '.services.'"$SERVICE"'.entrypoint' "$COMPOSE_FILE")
# Join array to string if needed
ENTRYPOINT_TYPE=$(yq e '.services.'"$SERVICE"'.entrypoint | type' "$COMPOSE_FILE")
if [ "$ENTRYPOINT_TYPE" = "!!seq" ]; then
  ENTRYPOINT=$(yq e '.services.'"$SERVICE"'.entrypoint | join(" ")' "$COMPOSE_FILE")
fi

CMD=$(yq e '.services.'"$SERVICE"'.command' "$COMPOSE_FILE")
# Join array to string if needed
CMD_TYPE=$(yq e '.services.'"$SERVICE"'.command | type' "$COMPOSE_FILE")
if [ "$CMD_TYPE" = "!!seq" ]; then
  CMD=$(yq e '.services.'"$SERVICE"'.command | join(" ")' "$COMPOSE_FILE")
fi

# Pre-run Tasks
udocker_check
udocker_prune
udocker_create "$CONTAINER_NAME" "$IMAGE_NAME"

# Main Task
if [ -n "$1" ]; then
    unset user_cmd
    user_cmd="$*"
    # 1. Interactive: User provides a command
    udocker_run "${ENV_ARGS[@]}" ${VOL_ARGS} "${PORT_ARGS[@]}" "$CONTAINER_NAME" "${user_cmd}"

elif [ "$ENTRYPOINT" != "null" ] || [ "$CMD" != "null" ]; then
    # 2. Compose Entrypoint/CMD specified in compose file
    UDOCKER_CMD="udocker_run"
    [ "$ENTRYPOINT" != "null" ] && UDOCKER_CMD+=" --entrypoint \"$ENTRYPOINT\""
    UDOCKER_CMD+=" "${ENV_ARGS[@]}" ${VOL_ARGS} "${PORT_ARGS[@]}"  \"$CONTAINER_NAME\""
    [ "$CMD" != "null" ] && UDOCKER_CMD+=" \"$CMD\""
    echo "Running with Compose Entrypoint/CMD:"
    echo $UDOCKER_CMD
    eval $UDOCKER_CMD

else
    # 3. Default: Use image's default Entrypoint and CMD
    echo "Running with image default (built-in) Entrypoint/CMD:"
    udocker_run "${ENV_ARGS[@]}" ${VOL_ARGS} "${PORT_ARGS[@]}" "$CONTAINER_NAME"
fi

exit $?
