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

IDLE_THRESHOLD=120  # seconds

echo "Checking recent $SERVICE logs for controller activity..."
LAST_CONTROLLER_LINE=$(docker compose logs "$SERVICE" --tail=200 --no-log-prefix 2>/dev/null | grep "Controller " | tail -1)

if [ -z "$LAST_CONTROLLER_LINE" ]; then
  echo "No controller activity found in recent logs. Restarting..."
  ./run.sh $TAG
  exit 0
fi

# Parse timestamp from log line: "2026-03-04 12:52:40.689 ..."
LAST_TS=$(echo "$LAST_CONTROLLER_LINE" | awk '{print $1 " " $2}' | cut -d. -f1)
echo "Last controller call: $LAST_TS"

# Log timestamps are UTC; force UTC for both parsing and current time
LAST_EPOCH=$(TZ=UTC date -d "$LAST_TS" +%s 2>/dev/null || TZ=UTC date -j -f "%Y-%m-%d %H:%M:%S" "$LAST_TS" +%s 2>/dev/null)
NOW_EPOCH=$(TZ=UTC date +%s)
DIFF=$((NOW_EPOCH - LAST_EPOCH))

echo "Last controller activity was ${DIFF}s ago (threshold: ${IDLE_THRESHOLD}s)"

if [ "$DIFF" -ge "$IDLE_THRESHOLD" ]; then
  echo "Service is idle. Restarting..."
  ./run.sh $TAG
else
  echo "not restarting - activity too recent"
  exit 1
fi
