#!/bin/bash
set -e

# ------------------------------------------------------------
# Usage check
# ------------------------------------------------------------
if [ $# -ne 1 ]; then
  echo "Usage: sudo $0 <config.json>"
  exit 1
fi

CONFIG_SRC="$1"

if [ ! -f "$CONFIG_SRC" ]; then
  echo "[install] Config file not found: $CONFIG_SRC"
  exit 1
fi

# ------------------------------------------------------------
# Constants
# ------------------------------------------------------------
SERVICE_NAME="pybus"
INSTALL_DIR="/opt/pybus"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
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

# ---- Copy necessary files ----
echo "[install] Copying files to $INSTALL_DIR"

# Core python + scripts
cp -v "$CURRENT_DIR/pybus.py" "$INSTALL_DIR/"
cp -v "$CURRENT_DIR/start_pybus.sh" "$INSTALL_DIR/"
cp -v "$CURRENT_DIR/stop_pybus.sh" "$INSTALL_DIR/"
cp -v "$CONFIG_SRC" "$CONFIG_DEST"

# ---- Ensure scripts are executable ----
chmod +x "$INSTALL_DIR/start_pybus.sh"
chmod +x "$INSTALL_DIR/stop_pybus.sh"

# ---- Create systemd service file ----
echo "[install] Creating systemd service: $SYSTEMD_FILE"

cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=pybus serial ↔ UDP bridge
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR

ExecStart=$INSTALL_DIR/start_pybus.sh $CONFIG_DEST
ExecStop=$INSTALL_DIR/stop_pybus.sh

Restart=always
RestartSec=2

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ---- Reload systemd ----
echo "[install] Reloading systemd"
systemctl daemon-reexec
systemctl daemon-reload

# ---- Enable service ----
echo "[install] Enabling service at boot"
systemctl enable "$SERVICE_NAME"

# ---- Give permission to write on pybus folder ----
chown -R "$SUDO_USER:$SUDO_USER" /opt/pybus

echo
echo "[install] Installation complete."
echo
echo "Next steps:"
echo "  Restart service : sudo systemctl restart $SERVICE_NAME"
echo "  Start service : sudo systemctl start $SERVICE_NAME"
echo "  Stop service  : sudo systemctl stop $SERVICE_NAME"
echo "  Status        : systemctl status $SERVICE_NAME"
echo "  Logs          : journalctl -u $SERVICE_NAME -f"
