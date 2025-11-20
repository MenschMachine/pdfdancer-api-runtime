#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"

source .env
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

TARGET="$1"

case "$TARGET" in
  blue|green)
    SERVICE_NAME="$TARGET"
    IMAGE_TAG="$TARGET"
    ;;
  main)
    SERVICE_NAME="green"
    IMAGE_TAG="main"
    ;;
  *)
    echo "USAGE: $0 [blue|green|main]"
    exit 69
    ;;
esac

export BACKEND_API_URL=http://pdfdancer-api-runtime-${SERVICE_NAME}-1:8080
docker pull ghcr.io/menschmachine/pdfdancer-api:${IMAGE_TAG}

if [ "$IMAGE_TAG" != "$SERVICE_NAME" ]; then
  docker tag ghcr.io/menschmachine/pdfdancer-api:${IMAGE_TAG} ghcr.io/menschmachine/pdfdancer-api:${SERVICE_NAME}
fi

docker compose up -d

# When using main target, shutdown the blue service
if [ "$TARGET" = "main" ]; then
  echo "Shutting down blue service..."
  docker compose stop blue
fi
