#!/bin/bash

CONFIG="configs/rc_drone.json"
PYTHON="python3"
PYBUS_SCRIPT="pybus.py"

# Require jq
if ! command -v jq &> /dev/null; then
  echo "jq is required (sudo apt install jq)"
  exit 1
fi

mkdir -p logs

# Iterate over instances
jq -r '.instances[].name' "$CONFIG" | while read -r NAME; do
  echo "Starting pybus instance: $NAME"

  nohup $PYTHON $PYBUS_SCRIPT \
    --config "$CONFIG" \
    --instance "$NAME" \
    > "logs/$NAME.log" 2>&1 &

  echo "  -> PID $!"
done

echo "All pybus instances started."

echo
echo "Verifying running pybus instances..."
echo "------------------------------------------------------------"

sleep 1

jq -r '.instances[].name' "$CONFIG" | while read -r NAME; do
  PID=$(pgrep -f "pybus.py.*--instance $NAME")

  if [ -n "$PID" ]; then
    echo "✔ Instance '$NAME' is running (PID: $PID)"
  else
    echo "✘ Instance '$NAME' is NOT running"
  fi
done

echo "------------------------------------------------------------"
