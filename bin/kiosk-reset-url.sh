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
  sleep 2
else
  echo "INFO No Chromium process found." >> "$LOGFILE"
fi

# --- Restart kiosk session ---
if [ -x "$SESSION_SCRIPT" ]; then
  echo "INFO Restarting kiosk session from $SESSION_SCRIPT" >> "$LOGFILE"
  nohup "$SESSION_SCRIPT" >> "$LOGFILE" 2>&1 &
else
  echo "ERROR Kiosk session script not found or not executable: $SESSION_SCRIPT" >> "$LOGFILE"
fi

echo "✅ Done." >> "$LOGFILE"
