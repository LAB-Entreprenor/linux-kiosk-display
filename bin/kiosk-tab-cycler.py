#!/usr/bin/env python3
import os, time, json, subprocess

# --- Dynamic paths ---
USER = os.environ.get("SUDO_USER") or os.environ.get("USER") or "pi"
USER_HOME = os.path.expanduser(f"~{USER}")

CONFIG_FILE = os.path.join(USER_HOME, "kiosk_config.json")
STATE_FILE = "/tmp/kiosk_state.json"
DEFAULT_INTERVAL = 60  # seconds


def read_config():
    """Load kiosk configuration, with fallbacks."""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f:
                cfg = json.load(f)
            return cfg
        except Exception as e:
            print(f"Error reading config: {e}")
    return {"urls": [], "cycle_interval": DEFAULT_INTERVAL}


def is_idle():
    """Check the /tmp state file written by kiosk-idle-reset."""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE) as f:
                data = json.load(f)
            return not data.get("active", False)
    except Exception:
        pass
    return True


def chromium_windows():
    """Return a list of Chromium window IDs."""
    try:
        output = subprocess.check_output(
            ["xdotool", "search", "--class", "chromium"], text=True
        )
        return output.strip().splitlines()
    except subprocess.CalledProcessError:
        return []


def open_missing_tabs(urls):
    """Ensure all URLs in the config are open in Chromium."""
    if not urls:
        return

    windows = chromium_windows()
    if not windows:
        print("No Chromium windows found; skipping tab open.")
        return

    first_window = windows[0]
    subprocess.run(["xdotool", "windowactivate", first_window], check=False)

    # Open new tabs for all missing URLs
    for url in urls[1:]:
        subprocess.run(["xdotool", "key", "ctrl+t"], check=False)
        time.sleep(0.3)
        subprocess.run(["xdotool", "type", "--delay", "10", url], check=False)
        subprocess.run(["xdotool", "key", "Return"], check=False)
        time.sleep(1)


def switch_tab():
    """Switch to the next Chromium tab."""
    subprocess.run(["xdotool", "key", "ctrl+Tab"], check=False)


def main():
    print("Kiosk Tab Cycler started.")
    cfg = read_config()
    urls = cfg.get("urls", [])
    interval = int(cfg.get("cycle_interval", DEFAULT_INTERVAL))

    if not urls:
        print("No URLs found in config file; exiting.")
        return

    print(f"Cycling every {interval}s between {len(urls)} URLs.")

    # Ensure all URLs are open initially
    open_missing_tabs(urls)

    while True:
        if is_idle():
            switch_tab()
        time.sleep(interval)


if __name__ == "__main__":
    main()
