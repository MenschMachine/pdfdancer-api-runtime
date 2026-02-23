#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"

source .env
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

PULL_ONLY=false
TAG="main"

while [[ $# -gt 0 ]]; do
  case $1 in
    --pull)
      PULL_ONLY=true
      shift
      ;;
    *)
      TAG="$1"
      shift
      ;;
  esac
done

# Determine service name and compose profiles based on tag
if [ "$TAG" = "blue" ]; then
  SERVICE_NAME="blue"
  export COMPOSE_PROFILES="blue-enabled"
elif [ "$TAG" = "green" ]; then
  SERVICE_NAME="green"
  export COMPOSE_PROFILES="blue-enabled"
else
  # For any other tag (including 'main'), use green service
  SERVICE_NAME="green"
  export COMPOSE_PROFILES=""
fi

IMAGE_TAG="$TAG"

export BACKEND_API_URL=http://pdfdancer-api-runtime-${SERVICE_NAME}-1:8080
docker pull ghcr.io/menschmachine/pdfdancer-api:${IMAGE_TAG}
docker pull ghcr.io/menschmachine/pdfdancer-pii-detection:latest

if [ "$PULL_ONLY" = true ]; then
  exit 0
fi

# Backup tenant database from Docker volume before deploy
BACKUP_FILE="$SCRIPTPATH/db/tenants.db.bak.$(date +%Y%m%d_%H%M%S)"
VOLUME_NAME=$(docker volume ls --format '{{.Name}}' | grep 'db-tenants$' | head -1)
if [ -n "$VOLUME_NAME" ]; then
  docker compose stop "$SERVICE_NAME" 2>/dev/null || true
  docker run --rm -v "$VOLUME_NAME":/db -v "$SCRIPTPATH/db":/backup alpine \
    cp /db/tenants.db "/backup/$(basename "$BACKUP_FILE")"
  echo "Tenant DB backed up to $BACKUP_FILE"
fi

if [ "$IMAGE_TAG" != "$SERVICE_NAME" ]; then
  docker tag ghcr.io/menschmachine/pdfdancer-api:${IMAGE_TAG} ghcr.io/menschmachine/pdfdancer-api:${SERVICE_NAME}
fi

docker compose up -d

# When not using blue tag, ensure blue service is stopped
if [ "$TAG" != "blue" ]; then
  docker compose stop blue 2>/dev/null || true
fi

# Restore cursor visibility (docker login can hide it)
tput cnorm 2>/dev/null || true
