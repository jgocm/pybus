#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo (root privileges required)."
  echo "Please re-run as: sudo $0"
  exit 1
fi

echo "[pybus] Searching for running pybus instances..."

# Find matching processes (exclude grep itself)
PIDS=$(ps -eo pid,cmd | grep "pybus.py" | grep -- "--config" | grep -v grep)

if [ -z "$PIDS" ]; then
  echo "No pybus instances are currently running."
  exit 0
fi

# Stop systemd services
echo
echo "Running pybus services:"
echo "------------------------------------------------------------"
EXISTING_UNITS=$(systemctl list-units 'pybus@*' --all --no-legend | awk '{print $1}')
echo "$EXISTING_UNITS"
echo "------------------------------------------------------------"
echo
echo "Stopping pybus services..."

for UNIT in $EXISTING_UNITS; do
  systemctl stop "$UNIT"
  echo "  → Stopped service $UNIT"
done

# Kill non-service processes
echo
echo "Running pybus processes:"
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
echo "Stopping pybus processes..."

while read -r LINE; do
  PID=$(echo "$LINE" | awk '{print $1}')
  kill "$PID"
  echo "  → Stopped PID $PID"
done <<< "$PIDS"

echo
echo "All pybus instances stopped."
