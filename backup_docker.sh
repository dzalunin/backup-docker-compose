#!/bin/bash

### Bash Environment Setup
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# set -o xtrace
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
IFS=$'\n'

function print_array {
  local IFS="$1"
  shift
  echo "\"$*\""
}

function backup_volume {
  local volume_name=$1
  local backup_destination=$2

  docker run --rm \
    --mount source=$volume_name,target=/data \
    -v $backup_destination:/backup \
    busybox \
    tar -czvf /backup/$volume_name.tar.gz /data
}

function backup_image {
  local image_short_id=$1
  local backup_destination=$2
  
  docker save --output "$backup_destination" "$image_short_id"
}

function backup_container_config {
  local container_id=$1
  local backup_destination=$2

  docker inspect "$container_id" > "$backup_destination/config.json"
}

function main {	
  local project_dir="${1:-$PWD}"
  if [ -f "$project_dir/docker-compose.yml" ]; then
    echo "[i] Found docker-compose config at $project_dir/docker-compose.yml"
  else
    echo "[X] Could not find a docker-compose.yml file in $project_dir"
    exit 1
  fi

  local backup_dir=$2  
  local project_name=$(basename "$project_dir")
  local manifest_file="$backup_dir/manifest.sh"

  mkdir -p "$backup_dir"
  echo "project_name=\"$project_name\"" > "$manifest_file"

  echo "[+] Backing up $project_name project to $backup_dir"
  project_backup_dir="$backup_dir/__$project_name"
  mkdir -p $project_backup_dir
  rsync -azP --exclude='.git' --delete $project_dir/ $project_backup_dir/

  cd $project_dir
  
  services=$(docker compose config --services)
  echo "services=$(print_array " " $services)" >> "$manifest_file"
  echo "declare -A images" >> "$manifest_file"
  for service_name in $services; do
    image_id=$(docker compose images -q "$service_name")
    image_name=$(docker image inspect --format '{{json .RepoTags}}' "$image_id" | jq -r '.[0]')
    image_short_id=$(echo $image_id | cut -c1-12)

    service_backup_dir="$backup_dir/$service_name"
    echo "[*] Backing up ${project_name}_${service_name} image to $service_backup_dir..."
    mkdir -p "$service_backup_dir"

    # save image
    image_backup_path="$service_backup_dir/image.tar"

    echo "    - Saving $image_name image to $image_backup_path"
    backup_image $image_short_id $image_backup_path
    echo "images[\"${service_name}\"]=\"$image_name\"" >> "$manifest_file"
    # echo "${service_name}_image=\"$image_name\"" >> "$manifest_file"
  done

  for service_name in $services; do
    container_id=$(docker compose ps -q "$service_name")
    if [[ -z "$container_id" ]]; then
        echo "    - Warning: $service_name has no container yet."
        echo "         (has it been started at least once?)"
        continue
    fi

    service_backup_dir="$backup_dir/$service_name"
    echo "[*] Backing up ${service_name} containers persistent data to $service_backup_dir..."
    mkdir -p "$service_backup_dir"

    # save config
    echo "    - Saving container config to ./$service_name/config.json"
    backup_container_config $container_id $service_backup_dir

    # save data volumes
    mkdir -p "$service_backup_dir/volumes"
    for volume_name in $(docker inspect -f '{{range .Mounts}}{{println .Name}}{{end}}' "$container_id"); do
        volume_dir="$service_backup_dir/volumes"

        echo "    - Saving $volume_name volume to $volume_dir"
        backup_volume $volume_name $volume_dir
    done
  done

}

main $@
