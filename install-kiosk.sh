#!/usr/bin/env bash
set -euo pipefail
set -x  # enable command trace for debugging

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

echo "Step 1: Installing dependencies..." | tee -a "$LOGFILE"
apt update -y >>"$LOGFILE" 2>&1
echo "apt update completed" | tee -a "$LOGFILE"

apt install -y \
  python3 python3-pip python3-evdev python3-venv git jq \
  xdotool unclutter x11-xserver-utils \
  xserver-xorg labwc xdg-utils >>"$LOGFILE" 2>&1
echo "Base dependencies installed" | tee -a "$LOGFILE"

# Chromium installation with safe check
echo "Step 1.1: Checking and installing Chromium..." | tee -a "$LOGFILE"
set +e  # temporarily disable exit-on-error
apt-cache show chromium-browser >/dev/null 2>&1
CHROMIUM_BROWSER_AVAILABLE=$?
apt-cache show chromium >/dev/null 2>&1
CHROMIUM_AVAILABLE=$?
set -e  # re-enable error exit

if [ $CHROMIUM_BROWSER_AVAILABLE -eq 0 ]; then
  echo "Installing chromium-browser..." | tee -a "$LOGFILE"
  apt install -y chromium-browser >>"$LOGFILE" 2>&1
  echo "Chromium-browser installation complete" | tee -a "$LOGFILE"
elif [ $CHROMIUM_AVAILABLE -eq 0 ]; then
  echo "Installing chromium..." | tee -a "$LOGFILE"
  apt install -y chromium >>"$LOGFILE" 2>&1
  echo "Chromium installation complete" | tee -a "$LOGFILE"
else
  echo "Chromium not available via apt. Skipping." | tee -a "$LOGFILE"
fi

echo "Step 2: Installing Python modules..." | tee -a "$LOGFILE"
pip3 install --upgrade pip >>"$LOGFILE" 2>&1
pip3 install flask >>"$LOGFILE" 2>&1
echo "Python modules installed" | tee -a "$LOGFILE"

echo "Step 3: Installing executables..." | tee -a "$LOGFILE"
install -Dm755 "$BIN_DIR/kiosk_manager.py"    "$SYSTEM_BIN/kiosk-manager.py"
install -Dm755 "$BIN_DIR/kiosk-session.sh"    "$SYSTEM_BIN/kiosk-session.sh"
install -Dm755 "$BIN_DIR/kiosk-tab-cycler.py" "$SYSTEM_BIN/kiosk-tab-cycler.py"
install -Dm755 "$BIN_DIR/kiosk-idle-reset.py" "$SYSTEM_BIN/kiosk-idle-reset.py"
install -Dm755 "$BIN_DIR/kiosk-reset-url.sh"  "$SYSTEM_BIN/kiosk-reset-url.sh"
echo "Executables installed" | tee -a "$LOGFILE"

echo "Step 4: Creating systemd services..." | tee -a "$LOGFILE"
mkdir -p "$SYSTEMD_DIR"

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
echo "systemd daemon reloaded" | tee -a "$LOGFILE"
systemctl enable --now kiosk.service kiosk-idle-reset.service kiosk-tab-cycler.service
echo "systemd services enabled and started" | tee -a "$LOGFILE"

echo "Step 5: Checking config file..." | tee -a "$LOGFILE"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating default config" | tee -a "$LOGFILE"
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
  echo "Existing config found, skipping" | tee -a "$LOGFILE"
fi

echo "Step 6: Creating desktop entry..." | tee -a "$LOGFILE"
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
echo "Desktop entry created" | tee -a "$LOGFILE"

chown "$USER_NAME:$USER_NAME" "$CONFIG_FILE" || true
echo "File ownership set" | tee -a "$LOGFILE"

echo "Kiosk installation complete" | tee -a "$LOGFILE"
echo "----------------------------------------------------------"
echo "Installed for user:  $USER_NAME"
echo "Config file:         $CONFIG_FILE"
echo "Executables:         $SYSTEM_BIN"
echo "Services installed:  kiosk.service, kiosk-idle-reset.service, kiosk-tab-cycler.service"
echo "Desktop entry:       $DESKTOP_FILE"
echo "Web Manager:         http://localhost:8080"
echo "Install log:         $LOGFILE"
echo "----------------------------------------------------------"
