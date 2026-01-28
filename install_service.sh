#!/bin/bash
set -e

SERVICE_NAME="pybus"
INSTALL_DIR="/opt/pybus"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CURRENT_DIR="$(pwd)"

echo "[install] Installing pybus service..."

# ---- Ensure script is run as root ----
if [ "$EUID" -ne 0 ]; then
  echo "[install] Please run as root (sudo ./install_service.sh)"
  exit 1
fi

# ---- Create install directory ----
echo "[install] Creating $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# ---- Copy necessary files ----
echo "[install] Copying files to $INSTALL_DIR"

# Core python + scripts
cp -v "$CURRENT_DIR/pybus.py" "$INSTALL_DIR/"
cp -v "$CURRENT_DIR/start_pybus.sh" "$INSTALL_DIR/"
cp -v "$CURRENT_DIR/stop_pybus.sh" "$INSTALL_DIR/"

# Config directory (if exists)
if [ -d "$CURRENT_DIR/configs" ]; then
  cp -rv "$CURRENT_DIR/configs" "$INSTALL_DIR/"
else
  echo "[install] WARNING: configs/ directory not found"
fi

# Logs directory
mkdir -p "$INSTALL_DIR/logs"

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
WorkingDirectory=/opt/pybus

ExecStart=/opt/pybus/start_pybus.sh
ExecStop=/opt/pybus/stop_pybus.sh

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
echo "  Start service : sudo systemctl start $SERVICE_NAME"
echo "  Stop service  : sudo systemctl stop $SERVICE_NAME"
echo "  Status        : systemctl status $SERVICE_NAME"
echo "  Logs          : journalctl -u $SERVICE_NAME -f"
