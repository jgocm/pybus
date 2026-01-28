#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <config.json>"
  exit 1
fi

CONFIG="$1"
PYTHON="python3"
PYBUS_SCRIPT="pybus.py"

if [ ! -f "$CONFIG" ]; then
  echo "Config file not found: $CONFIG"
  exit 1
fi

# Require jq
if ! command -v jq &> /dev/null; then
  echo "jq is required (sudo apt install jq)"
  exit 1
fi

mkdir -p logs

# Iterate over instances
jq -r '.instances[].name' "$CONFIG" | while read -r NAME; do
  echo "Starting pybus instance: $NAME"

  $PYTHON $PYBUS_SCRIPT \
    --config "$CONFIG" \
    --instance "$NAME" &

  echo "  -> PID $!"
done

echo "All pybus instances started."

echo
echo "Verifying running pybus instances..."
echo "------------------------------------------------------------"

sleep 5

jq -r '.instances[].name' "$CONFIG" | while read -r NAME; do
  PID=$(pgrep -f "pybus.py.*--instance $NAME")

  if [ -n "$PID" ]; then
    echo "✔ Instance '$NAME' is running (PID: $PID)"
  else
    echo "✘ Instance '$NAME' is NOT running"
  fi
done

echo "------------------------------------------------------------"
