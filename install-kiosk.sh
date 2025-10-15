#!/usr/bin/env bash
# ----------------------------------------------------------
# Raspberry Pi / Linux Unified Kiosk Installer (Root Only)
# ----------------------------------------------------------
# Installs kiosk environment system-wide, creates services,
# desktop launcher, and configuration for the main user.
# ----------------------------------------------------------

set -euo pipefail

# --- Require root ---
if [ "$EUID" -ne 0 ]; then
  echo "Warning: This installer must be run as root (use: sudo ./install-kiosk.sh)"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$PROJECT_DIR/bin"
USER_NAME="$(logname 2>/dev/null || whoami)"
USER_HOME="$(eval echo "~$USER_NAME")"
SYSTEM_BIN="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
DESKTOP_DIR="/usr/local/share/applications"
CONFIG_FILE="$USER_HOME/kiosk_config.json"
LOGFILE="/tmp/kiosk-install.log"

echo "Installing kiosk environment for user '$USER_NAME'..." | tee "$LOGFILE"

# --- 1. Dependencies ---
echo "Installing dependencies..." | tee -a "$LOGFILE"
apt update -y >>"$LOGFILE" 2>&1
apt install -y \
  python3 python3-pip python3-evdev \
  xdotool unclutter chromium-browser \
  xserver-xorg x11-xserver-utils \
  labwc jq >>"$LOGFILE" 2>&1

# --- 2. Python packages ---
echo "Installing Python modules..." | tee -a "$LOGFILE"
pip3 install flask >>"$LOGFILE" 2>&1

# --- 3. Install executables ---
echo "Installing executables from $BIN_DIR to $SYSTEM_BIN..." | tee -a "$LOGFILE"
install -Dm755 "$BIN_DIR/kiosk_manager.py"    "$SYSTEM_BIN/kiosk-manager.py"
install -Dm755 "$BIN_DIR/kiosk-session.sh"    "$SYSTEM_BIN/kiosk-session.sh"
install -Dm755 "$BIN_DIR/kiosk-tab-cycler.py" "$SYSTEM_BIN/kiosk-tab-cycler.py"
install -Dm755 "$BIN_DIR/kiosk-idle-reset.py" "$SYSTEM_BIN/kiosk-idle-reset.py"
install -Dm755 "$BIN_DIR/kiosk-reset-url.sh"  "$SYSTEM_BIN/kiosk-reset-url.sh"

# --- 4. Generate systemd services ---
echo "Generating systemd service files..." | tee -a "$LOGFILE"
mkdir -p "$SYSTEMD_DIR"

# kiosk.service
cat <<EOF > "$SYSTEMD_DIR/kiosk.service"
[Unit]
Description=Raspberry Pi Kiosk Session
After=graphical.target network.target

[Service]
User=$USER_NAME
Group=$USER_NAME
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME)
ExecStart=$SYSTEM_BIN/kiosk-session.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

# kiosk-idle-reset.service
cat <<EOF > "$SYSTEMD_DIR/kiosk-idle-reset.service"
[Unit]
Description=Kiosk Idle Reset Service
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 $SYSTEM_BIN/kiosk-idle-reset.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# kiosk-tab-cycler.service
cat <<EOF > "$SYSTEMD_DIR/kiosk-tab-cycler.service"
[Unit]
Description=Kiosk Tab Cycler Service
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 $SYSTEM_BIN/kiosk-tab-cycler.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now kiosk.service kiosk-idle-reset.service kiosk-tab-cycler.service

# --- 5. Config file ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating default configuration at $CONFIG_FILE" | tee -a "$LOGFILE"
  cat <<EOF >"$CONFIG_FILE"
{
  "urls": [
    "https://reise.skyss.no/stops/stop-group/NSR:StopPlace:32266",
    "https://yr.no/place/Norway/Vestland/Bergen/"
  ],
  "cycle_interval": 60,
  "idle_timeout": 600
}
EOF
else
  echo "Keeping existing configuration: $CONFIG_FILE" | tee -a "$LOGFILE"
fi

# --- 6. Generate .desktop launcher ---
echo "Generating system-wide desktop entry..." | tee -a "$LOGFILE"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/KioskManager.desktop"
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=Kiosk Manager
Exec=/usr/bin/python3 $SYSTEM_BIN/kiosk-manager.py
Icon=chromium
Terminal=false
Categories=Network;Utility;
Comment=Configure and monitor Raspberry Pi kiosk environment
EOF

chmod 644 "$DESKTOP_FILE"
update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

# --- 7. Ownership fix ---
chown "$USER_NAME:$USER_NAME" "$CONFIG_FILE" || true

# --- 8. Summary ---
echo "Kiosk installation complete!" | tee -a "$LOGFILE"
echo "----------------------------------------------------------"
echo "Installed for user:  $USER_NAME"
echo "Config file:         $CONFIG_FILE"
echo "Executables:         $SYSTEM_BIN"
echo "Services installed:  kiosk.service, kiosk-idle-reset.service, kiosk-tab-cycler.service"
echo "Desktop entry:       $DESKTOP_FILE"
echo "Web Manager:         http://localhost:8080"
echo "Install log:         $LOGFILE"
echo "----------------------------------------------------------"
echo "To restart all services manually:"
echo "sudo systemctl restart kiosk.service kiosk-idle-reset.service kiosk-tab-cycler.service"
