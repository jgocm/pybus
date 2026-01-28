#!/bin/bash
set -e

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: sudo $0 <config.json> [-s]"
  exit 1
fi

CONFIG_SRC="$1"
START_SERVICES=false

if [ "$2" == "-s" ]; then
  START_SERVICES=true
elif [ -n "$2" ]; then
  echo "Unknown option: $2"
  echo "Usage: sudo $0 <config.json> [-s]"
  exit 1
fi


# ------------------------------------------------------------
# Constants
# ------------------------------------------------------------
SERVICE_NAME="pybus"
INSTALL_DIR="/opt/pybus"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}@.service"
CURRENT_DIR="$(pwd)"

CONFIG_BASENAME="$(basename "$CONFIG_SRC")"
CONFIG_DEST="$INSTALL_DIR/configs/$CONFIG_BASENAME"

echo "[install] Installing pybus service using config: $CONFIG_BASENAME"

# ---- Ensure script is run as root ----
if [ "$EUID" -ne 0 ]; then
  echo "[install] Please run as root (sudo ./install_service.sh <config.json>)"
  exit 1
fi

# ---- Create install directory ----
echo "[install] Creating $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/configs"
mkdir -p "$INSTALL_DIR/logs"

# ---- Copy necessary files ----
echo "[install] Copying files to $INSTALL_DIR"

# Core python + scripts
cp -v "$CURRENT_DIR/pybus.py" "$INSTALL_DIR/"
cp -v "$CONFIG_SRC" "$CONFIG_DEST"

# ---- Create systemd service file ----
echo "[install] Creating systemd service: $SYSTEMD_FILE"

cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=pybus serial ↔ UDP bridge instance (%i)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR

ExecStart=/usr/bin/python3 $INSTALL_DIR/pybus.py \
  --config $CONFIG_DEST \
  --instance %i

Restart=always
RestartSec=2

StandardOutput=journal
StandardError=journal

# Hardening (optional but recommended)
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ---- Give permission to write on pybus folder ----
chown -R "$SUDO_USER:$SUDO_USER" /opt/pybus

# ---- Remove obsolete services ----
echo "[install] Checking for obsolete pybus services..."

JSON_INSTANCES=$(jq -r '.instances[].name' "$CONFIG_SRC")

echo "[install] Current instances in config:"
echo "$JSON_INSTANCES"

EXISTING_UNITS=$(systemctl list-units 'pybus@*' --all --no-legend | awk '{print $1}')

echo "[install] Existing pybus units:"
echo "$EXISTING_UNITS"

for UNIT in $EXISTING_UNITS; do
  # Skip template
  if [ "$UNIT" = "pybus@.service" ]; then
    continue
  fi

  INSTANCE_NAME="${UNIT#pybus@}"
  INSTANCE_NAME="${INSTANCE_NAME%.service}"

  if ! echo "$JSON_INSTANCES" | grep -qx "$INSTANCE_NAME"; then
    echo "  → Removing obsolete service: $UNIT"

    # Stop
    systemctl stop "$UNIT"

    # Disable (removes symlink)
    systemctl disable "$UNIT" >/dev/null 2>&1 || true

    # Clear failed state
    systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
  fi
done
echo "[install] Obsolete service check complete."

# ---- Reload systemd ----
echo "[install] Reloading systemd"
systemctl daemon-reexec
systemctl daemon-reload

# ---- Enable pybus and start instances based on config file ----
echo "[install] Enabling pybus instances"

jq -r '.instances[].name' "$CONFIG_SRC" | while read -r NAME; do
  echo "  → Enabling pybus@$NAME"
  systemctl enable "pybus@$NAME"
  if $START_SERVICES; then
    echo "  → Starting pybus@$NAME"
    systemctl restart "pybus@$NAME"
  fi
done

echo
echo "[install] Installation complete."
echo
echo "Next steps:"
echo "  Enable service  : sudo systemctl enable pybus@<instance>"
echo "  Restart service : sudo systemctl restart pybus@<instance>"
echo "  Start service   : sudo systemctl start pybus@<instance>"
echo "  Stop service    : sudo systemctl stop pybus@<instance>"
echo "  Status          : systemctl status pybus@<instance>"
echo "  Logs            : journalctl -u pybus@<instance> -f"
