# Backup / restore docker compose project

## Getting started

Install packages:
- `rsync`
- `jq`  

Clone repository

## Backup

```
./backup_docker.sh <project directory> <backup directory>
```
- project directory - docker-compose.yml location.
- backup directory - directory for backup 

Example

```sh
sudo /home/ubuntu/backup/backup_docker_compose.sh /opt/app /home/ubuntu/backup
tar -czvf /home/ubuntu/backup/arch.tar.gz -C /home/ubuntu/backup/app ./
```

## Restore

```
./restory_docker.sh <backup directory> <project directory>
```
- project directory - docker-compose.yml location.
- backup directory - directory with backup

Example

```sh
tar -xvzf /home/ubuntu/backup/arch.tar.gz -C /home/ubuntu/backup/
sudo /home/ubuntu/restore_docker.sh /home/ubuntu/backup /opt
```