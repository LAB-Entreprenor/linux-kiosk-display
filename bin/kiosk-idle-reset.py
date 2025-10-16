#!/usr/bin/env python3
import os, time, glob, subprocess, select, json
from evdev import InputDevice, ecodes

# --- Dynamic path setup ---
USER = os.environ.get("SUDO_USER") or os.environ.get("USER") or "pi"
USER_HOME = os.path.expanduser(f"~{USER}")

CONFIG_FILE = os.path.join(USER_HOME, "kiosk_config.json")
STATE_FILE = "/tmp/kiosk_state.json"
RESET_SCRIPT = "/usr/local/bin/kiosk-reset-url.sh"
DEFAULT_IDLE = 600  # fallback idle time (10 minutes)

ALT_KEYCODES = {ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT}
F4_KEYCODE = ecodes.KEY_F4


def load_idle_timeout():
    """Read idle_timeout from the kiosk config or use fallback."""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                cfg = json.load(f)
            return int(cfg.get("idle_timeout", DEFAULT_IDLE))
    except Exception as e:
        print(f"Error loading config: {e}")
    return DEFAULT_IDLE


def write_state(active):
    """Write the current active/idle state to /tmp."""
    data = {"active": active, "timestamp": time.time()}
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(data, f)
    except Exception as e:
        print(f"Error writing state: {e}")


def chromium_running():
    """Check if Chromium is currently running."""
    try:
        subprocess.run(
            ["pgrep", "chromium"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def wait_for_chromium(timeout=30):
    """Wait for Chromium to start after reset."""
    start = time.time()
    while time.time() - start < timeout:
        if chromium_running():
            print("Chromium restarted successfully.")
            return True
        time.sleep(1)
    print("Chromium did not restart within timeout.")
    return False


def get_input_devices():
    """Collect all readable input devices."""
    devices = []
    for path in glob.glob("/dev/input/event*"):
        if os.access(path, os.R_OK):
            try:
                devices.append(InputDevice(path))
            except Exception as e:
                print(f"Cannot access {path}: {e}")
    return devices


def stop_all_services():
    """Stop all kiosk-related services for troubleshooting."""
    services = [
        "kiosk.service",
        "kiosk-idle-reset.service",
        "kiosk-tab-cycler.service",
    ]
    print("ALT+F4 detected — stopping all kiosk services for troubleshooting.")
    for service in services:
        try:
            subprocess.run(["systemctl", "stop", service], check=False)
        except Exception as e:
            print(f"Error stopping {service}: {e}")


def main():
    last_activity = time.time()
    devices = get_input_devices()
    idle_seconds = load_idle_timeout()
    print(f"Monitoring {len(devices)} input devices — idle timeout = {idle_seconds}s")

    write_state(True)

    pressed_keys = set()

    while True:
        # Periodically re-read config in case idle timeout changes
        idle_seconds = load_idle_timeout()

        r, _, _ = select.select([d.fd for d in devices], [], [], 1)
        now = time.time()

        if r:
            for d in devices:
                if d.fd in r:
                    for ev in d.read():
                        if ev.type == ecodes.EV_KEY:
                            if ev.value == 1:  # key down
                                pressed_keys.add(ev.code)
                                # Detect ALT+F4 combination
                                if F4_KEYCODE in pressed_keys and pressed_keys & ALT_KEYCODES:
                                    stop_all_services()
                                    return
                            elif ev.value == 0:  # key up
                                pressed_keys.discard(ev.code)

                        elif ev.type in (ecodes.EV_ABS, ecodes.EV_REL):
                            last_activity = now
                            write_state(True)

        elif now - last_activity >= idle_seconds:
            print(f"Idle for {idle_seconds}s — restarting kiosk session...")
            subprocess.run([RESET_SCRIPT], check=False)
            wait_for_chromium(timeout=30)
            write_state(False)
            last_activity = now


if __name__ == "__main__":
    main()
