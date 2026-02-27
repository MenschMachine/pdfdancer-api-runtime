#!/bin/bash -e

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd "$SCRIPTPATH"

TAG="${1:-}"

echo "Pulling latest images..."
./run.sh --pull $TAG

# Determine which service to check logs for (mirrors run.sh logic)
if [ "$TAG" = "blue" ]; then
  SERVICE="blue"
else
  SERVICE="green"
fi

echo "Checking recent $SERVICE logs for activity..."
LOGS=$(docker compose logs "$SERVICE" --tail=10 --no-log-prefix 2>/dev/null)

# Count consecutive trailing lines matching cleanup pattern
CONSECUTIVE=0
while IFS= read -r line; do
  if echo "$line" | grep -q "SessionCleanupService Session cleanup completed"; then
    CONSECUTIVE=$((CONSECUTIVE + 1))
  else
    CONSECUTIVE=0
  fi
done <<< "$LOGS"

if [ "$CONSECUTIVE" -ge 2 ]; then
  echo "Service is idle ($CONSECUTIVE consecutive cleanup lines). Restarting..."
  ./run.sh $TAG
else
  echo "not restarting - activity encountered"
  exit 1
fi
