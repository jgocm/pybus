#!/bin/bash

#!/bin/bash
set -e

echo "[pybus] Searching for running pybus instances..."
echo

# Find matching processes (exclude grep itself)
PIDS=$(ps -eo pid,cmd | grep "pybus.py" | grep -- "--config" | grep -v grep)

if [ -z "$PIDS" ]; then
  echo "No pybus instances are currently running."
  exit 0
fi

echo "Running pybus instances:"
echo "------------------------------------------------------------"

# Display instances
while read -r LINE; do
  PID=$(echo "$LINE" | awk '{print $1}')
  CMD=$(echo "$LINE" | cut -d' ' -f2-)

  INSTANCE=$(echo "$CMD" | sed -n 's/.*--instance \([^ ]*\).*/\1/p')

  echo "PID: $PID | Instance: ${INSTANCE:-unknown}"
done <<< "$PIDS"

echo "------------------------------------------------------------"
echo
echo "Stopping pybus instances..."

# Kill them
while read -r LINE; do
  PID=$(echo "$LINE" | awk '{print $1}')
  kill "$PID"
  echo "  → Stopped PID $PID"
done <<< "$PIDS"

echo
echo "All pybus instances stopped."
