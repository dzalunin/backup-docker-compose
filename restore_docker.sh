#!/bin/bash

### Bash Environment Setup
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
#set -o xtrace
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
IFS=$'\n'


function restore_volume {
  local backup_path=$1
  local volume_name=$2

  local backup_file=$(basename "$backup_path")
  local backup_dir=$(dirname "$backup_path")

  if [ ! -f "$backup_path" ]; then
      echo "[X] Could not find volume archive $backup_file in $backup_dir"
      exit 1
  fi

  docker run --rm \
    --mount source=$volume_name,target=/data \
    -v $backup_dir:/backup \
    busybox \
    tar -xzvf /backup/$backup_file -C /
}

function restore_image {
  local image_backup_path=$1
  local image_name=$2

  if [ ! -f "$image_backup_path" ]; then
      echo "[X] Could not find image archive in $image_backup_path"
      exit 1
  fi

  if [ -f "$image_backup_path" ]; then
    image_id=$(docker load < "$image_backup_path" | awk -F : '{print $3}')  
    docker tag $image_id $image_name
  fi  
}

function main {
  local backup_dir="${1:-$PWD}"
  local dst_dir=$2     
  local manifest_file="$backup_dir/manifest.sh"

  if [ -f "$manifest_file" ]; then
    echo "[i] Found manifest.sh at $backup_dir"
  else
    echo "[X] Could not find a manifest.sh file in $backup_dir"
    exit 1
  fi

  source $manifest_file

  local project_dir="$dst_dir/$project_name"
  local project_backup_dir="$backup_dir/__$project_name"

  echo "[+] Restore project \"$project_name\" from \"$project_backup_dir\" to \"$project_dir\""
  mkdir -p $project_dir
  if [ -z "$(find $project_dir -type d -empty)" ]; then
    echo "[X] Directory $project_dir is not empty"
    exit 1
  fi

  rsync -azP --delete $project_backup_dir/ $project_dir/

  services=$(echo $services | sed 's/\s/\n/g')
  for service_name in $services; do
    service_backup_dir="$backup_dir/$service_name"
    echo "[*] Restoring image for service ${project_name}_${service_name}..."

    image_backup_path="$service_backup_dir/image.tar"
    image_name=${images["$service_name"]}
    echo "    - Loading $image_name image from $image_backup_path"
    restore_image $image_backup_path $image_name
  done

  cd $project_dir
  echo "[*] Initializing project ${project_name} in $project_dir..."
  docker compose up --no-start

  for service_name in $services; do
    service_backup_dir="$backup_dir/$service_name"

    volumes_dir="$service_backup_dir/volumes"
    if [ ! -z "$(find $volumes_dir -type d -empty)" ]; then
      continue
    fi

    echo "[*] Restoring volumes for service ${project_name}_${service_name}..."
    for volume_backup_file in $(ls $volumes_dir); do
      volume_backup_path=$volumes_dir/$volume_backup_file
      volume_name=${volume_backup_file%%.*}

      echo "    - Restoring $volume_name volume from $volume_backup_path"
      restore_volume $volume_backup_path $volume_name
    done
  done

}

main $@