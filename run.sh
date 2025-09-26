#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"

source .env
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

BLUE_OR_GREEN="$1"
if test "$BLUE_OR_GREEN" == "green" || test "$BLUE_OR_GREEN" == "blue"; then
  export BACKEND_API_URL=http://pdfdancer-api-runtime-${BLUE_OR_GREEN}-1:8080
  docker pull ghcr.io/menschmachine/pdfdancer-api:staging
  docker compose up -d
else
  echo "USAGE: $0 [blue|green]"
  exit 69
fi

