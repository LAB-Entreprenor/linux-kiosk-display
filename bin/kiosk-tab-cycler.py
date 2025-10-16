#!/usr/bin/env python3
import os
import time
import json
import subprocess

# --- Configuration ---
STATE_FILE = "/tmp/kiosk_state.json"
DEFAULT_INTERVAL = 90  # seconds
LOGFILE = "/tmp/kiosk-tab-cycler.log"


def read_cycle_interval():
    """Read the cycle interval from the kiosk config (if available)."""
    user = os.environ.get("SUDO_USER") or os.environ.get("USER") or "pi"
    config_file = os.path.expanduser(f"~{user}/kiosk_config.json")

    if os.path.exists(config_file):
        try:
            with open(config_file) as f:
                cfg = json.load(f)
            interval = int(cfg.get("cycle_interval", DEFAULT_INTERVAL))
            return interval
        except Exception as e:
            print(f"Error reading config: {e}", file=open(LOGFILE, "a"))
    return DEFAULT_INTERVAL


def is_idle():
    """Check if the system is idle according to /tmp/kiosk_state.json."""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE) as f:
                data = json.load(f)
            return not data.get("active", False)
    except Exception:
        pass
    return True


def switch_tab():
    """Send ctrl+Tab to Chromium."""
    try:
        subprocess.run(["xdotool", "key", "ctrl+Tab"], check=False)
    except Exception as e:
        with open(LOGFILE, "a") as log:
            log.write(f"Error switching tab: {e}\n")


def main():
    interval = read_cycle_interval()
    print(f"Tab cycler running (interval: {interval}s, idle-only mode).")

    while True:
        if is_idle():
            with open(LOGFILE, "a") as log:
                log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - Idle detected, switching tab\n")
            switch_tab()
        time.sleep(interval)


if __name__ == "__main__":
    main()
