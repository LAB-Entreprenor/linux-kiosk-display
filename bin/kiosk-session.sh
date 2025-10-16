#!/usr/bin/env bash
# --------------------------------------------------
# Raspberry Pi Unified Kiosk Launcher (Dynamic)
# --------------------------------------------------
# Automatically detects the current user and home directory.
# Starts the Flask Kiosk Manager (if not already running),
# then opens Chromium in kiosk mode using the config file.
# --------------------------------------------------

# --- Detect current user & environment ---
USER_NAME="$(whoami)"
USER_HOME="$(eval echo "~$USER_NAME")"

CONFIG="$USER_HOME/kiosk_config.json"
FALLBACK_URL="http://0.0.0.0:8080"
MANAGER_APP="/usr/local/bin/kiosk-manager.py"
LOGFILE="/tmp/kiosk-session.log"
URL=""

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting kiosk session for user: $USER_NAME" >> "$LOGFILE"

# --- Start Flask manager if not already running ---
if pgrep -f "$MANAGER_APP" > /dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Kiosk Manager already running." >> "$LOGFILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Kiosk Manager..." >> "$LOGFILE"
  /usr/bin/python3 "$MANAGER_APP" > /tmp/kiosk-manager.log 2>&1 &
  sleep 2  # allow Flask to initialize
fi

# --- Determine URLs to open ---
URLS=()
if [ -f "$CONFIG" ]; then
  mapfile -t URLS < <(jq -r '.urls[]' "$CONFIG" 2>/dev/null | grep -v '^null$')
fi

# Fallback if none found
if [ ${#URLS[@]} -eq 0 ]; then
  URLS=("$FALLBACK_URL")
fi

# Join URLs into one line
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching Chromium with URLs: ${URLS[*]}" >> "$LOGFILE"


# --- Fallback if no valid URL found ---
if [ -z "$URL" ]; then
  URL="$FALLBACK_URL"
fi

# --- Prevent screen blanking & hide cursor ---
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.1 -root &

sleep 2  # ensure display is ready

# --- Launch Chromium in kiosk mode ---
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching Chromium with URL: $URL" >> "$LOGFILE"

chromium \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --no-first-run \
  --disable-translate \
  --start-maximized \
  --disable-features=TranslateUI \
  --enable-features=OverlayScrollbar \
  --password-store=basic \
  "${URLS[@]}"
