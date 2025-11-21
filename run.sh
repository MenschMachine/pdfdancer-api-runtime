#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"

source .env
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

TAG="${1:-main}"

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

if [ "$IMAGE_TAG" != "$SERVICE_NAME" ]; then
  docker tag ghcr.io/menschmachine/pdfdancer-api:${IMAGE_TAG} ghcr.io/menschmachine/pdfdancer-api:${SERVICE_NAME}
fi

docker compose up -d

# When not using blue tag, ensure blue service is stopped
if [ "$TAG" != "blue" ]; then
  docker compose stop blue 2>/dev/null || true
fi
