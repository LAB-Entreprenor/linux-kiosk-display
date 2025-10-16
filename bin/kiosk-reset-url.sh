#!/usr/bin/env bash
# --------------------------------------------------
# Raspberry Pi Kiosk Reset Script
# --------------------------------------------------
# Stops any running Chromium processes and relaunches
# the kiosk session, which reloads the proper URLs.
# --------------------------------------------------

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME="$(eval echo "~$USER_NAME")"
SESSION_SCRIPT="/usr/local/bin/kiosk-session.sh"
LOGFILE="/tmp/kiosk-reset.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Resetting kiosk session..." >> "$LOGFILE"

# --- Kill all running Chromium instances ---
if pgrep chromium >/dev/null; then
  echo "INFO Killing Chromium..." >> "$LOGFILE"
  pkill -f chromium
  sleep 1
else
  echo "INFO No Chromium process found." >> "$LOGFILE"
fi

# --- Restart kiosk service via systemd ---
SERVICE="kiosk.service"
echo "INFO Restarting $SERVICE via systemd" >> "$LOGFILE"

if systemctl is-active --quiet "$SERVICE"; then
  systemctl restart "$SERVICE" >> "$LOGFILE" 2>&1
else
  systemctl start "$SERVICE" >> "$LOGFILE" 2>&1
fi

echo "INFO Systemd restart complete." >> "$LOGFILE"
