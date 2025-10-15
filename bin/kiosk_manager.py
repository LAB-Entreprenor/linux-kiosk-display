#!/usr/bin/env python3
"""
Raspberry Pi Kiosk Manager
--------------------------
Web interface to configure the kiosk environment:
- Manage URLs to cycle through
- Adjust cycle interval and idle timeout
- Restart background services on save
"""

from flask import Flask, request, redirect, render_template_string, url_for, flash, get_flashed_messages
import json, os, subprocess, traceback

# --- Dynamic user detection ---
USER = os.environ.get("SUDO_USER") or os.environ.get("USER") or "pi"
USER_HOME = os.path.expanduser(f"~{USER}")
CONFIG = os.path.join(USER_HOME, "kiosk_config.json")

# --- Flask setup ---
app = Flask(__name__)
app.secret_key = "kioskmanager"

TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Raspberry Pi Kiosk Manager</title>
<style>
body {
  font-family: sans-serif;
  margin: 2em;
  background: #fafafa;
  color: #222;
}
h1 { margin-bottom: 0.2em; }
h2 {
  font-weight: normal;
  font-size: 1rem;
  color: #555;
  margin-top: 0;
  margin-bottom: 1.5em;
}
table {
  border-collapse: collapse;
  width: 100%%;
  margin-bottom: 1em;
}
th, td {
  padding: 0.5em;
  border-bottom: 1px solid #ddd;
}
input[type=text] {
  width: 98%%;
  min-width: 500px;
  padding: 0.4em;
  box-sizing: border-box;
}
input[type=number] {
  width: 120px;
  padding: 0.4em;
  box-sizing: border-box;
}
button {
  padding: 0.4em 0.8em;
  margin: 0.2em;
  cursor: pointer;
}
fieldset {
  border: 1px solid #ccc;
  padding: 1em;
  margin-top: 1.5em;
  background: #fff;
}
legend { font-weight: bold; }
.flash-success {
  background: #d4edda;
  color: #155724;
  padding: 0.6em;
  border: 1px solid #c3e6cb;
  margin-bottom: 1em;
  border-radius: 4px;
  opacity: 1;
  transition: opacity 1s ease-out;
}
.flash-error {
  background: #f8d7da;
  color: #721c24;
  padding: 0.6em;
  border: 1px solid #f5c6cb;
  margin-bottom: 1em;
  border-radius: 4px;
  opacity: 1;
  transition: opacity 1s ease-out;
}
label {
  display: block;
  margin-top: 0.5em;
  font-weight: bold;
}
.desc {
  font-size: 0.9em;
  color: #666;
  margin-bottom: 0.8em;
}
footer {
  font-size: 0.8em;
  color: #888;
  margin-top: 1.5em;
  border-top: 1px solid #ddd;
  padding-top: 1em;
}
</style>
<script>
// auto-hide flash messages after 3 seconds
window.addEventListener("DOMContentLoaded", () => {
  setTimeout(() => {
    document.querySelectorAll('.flash-success, .flash-error').forEach(el => {
      el.style.opacity = 0;
      setTimeout(() => el.remove(), 1000);
    });
  }, 3000);
});
</script>
</head>
<body>
<h1>🖥️ Raspberry Pi Kiosk Manager</h1>
<h2>Configure and control the kiosk URLs, cycle timing, and idle behavior.</h2>

{% for category, msg in messages %}
  <div class="flash-{{ category }}">{{ msg }}</div>
{% endfor %}

<!-- --- Website Management Table --- -->
<fieldset>
  <legend>Websites to Cycle</legend>
  <table>
    <tr><th>#</th><th>URL</th><th>Action</th></tr>

    {% for url in urls %}
    <tr>
      <form method="post" action="{{ url_for('remove', index=loop.index0) }}">
        <td>{{ loop.index }}</td>
        <td><input type="text" name="urls" value="{{ url }}" readonly></td>
        <td><button type="submit">❌ Remove</button></td>
      </form>
    </tr>
    {% endfor %}

    <tr>
      <form method="post" action="{{ url_for('add') }}">
        <td>+</td>
        <td><input type="text" name="new_url" placeholder="Add new website URL..."></td>
        <td><button type="submit">➕ Add</button></td>
      </form>
    </tr>
  </table>
</fieldset>

<!-- --- Save Configuration Form --- -->
<form method="post" action="{{ url_for('save') }}">
  <!-- Hidden inputs preserve URLs when saving -->
  {% for url in urls %}
    <input type="hidden" name="urls" value="{{ url }}">
  {% endfor %}

  <fieldset>
    <legend>Cycle & Idle Settings</legend>

    <label for="cycle_interval">Cycle interval (seconds):</label>
    <input type="number" id="cycle_interval" name="cycle_interval" value="{{ cycle_interval }}">
    <p class="desc">How long each webpage stays visible before automatically switching to the next one.</p>

    <label for="idle_timeout">Idle timeout (seconds):</label>
    <input type="number" id="idle_timeout" name="idle_timeout" value="{{ idle_timeout }}">
    <p class="desc">Time without any touch or mouse input before returning to the default homepage.</p>
  </fieldset>

  <button type="submit">💾 Save All</button>
</form>

<footer>
<p>Configuration file: <code>{{ path }}</code></p>
<p>Web Manager running as <strong>{{ user }}</strong></p>
</footer>
</body>
</html>
"""



# --- Flash helpers ---
def flash_error(msg):
    flash(msg, "error")

def flash_success(msg):
    flash(msg, "success")

# --- Config handling ---
def load_config():
    """Load JSON configuration, creating defaults if missing."""
    try:
        if not os.path.exists(CONFIG):
            os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
            default_cfg = {"urls": [], "cycle_interval": 60, "idle_timeout": 600}
            save_config(default_cfg)
            return default_cfg
        with open(CONFIG) as f:
            return json.load(f)
    except Exception as e:
        flash_error(f"Error loading config: {e}")
        return {"urls": [], "cycle_interval": 60, "idle_timeout": 600}

def save_config(cfg):
    """Save configuration safely."""
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG, "w") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        flash_error(f"Error saving config: {e}")
        traceback.print_exc()

def restart_services():
    """Restart kiosk background services to apply new settings."""
    try:
        for svc in ("kiosk-tab-cycler", "kiosk-idle-reset"):
            subprocess.run(["systemctl", "restart", f"{svc}.service"], check=False)
    except Exception as e:
        flash_error(f"⚠️ Service restart failed: {e}")

# --- Routes ---
@app.route("/")
def index():
    cfg = load_config()
    messages = get_flashed_messages(with_categories=True)
    return render_template_string(
        TEMPLATE,
        urls=cfg.get("urls", []),
        cycle_interval=cfg.get("cycle_interval", 60),
        idle_timeout=cfg.get("idle_timeout", 600),
        path=CONFIG,
        messages=messages,
        user=USER,
    )

@app.post("/add")
def add():
    try:
        cfg = load_config()
        new_url = request.form.get("new_url", "").strip()
        if new_url:
            urls = cfg.setdefault("urls", [])
            if new_url not in urls:
                urls.append(new_url)
                save_config(cfg)
                flash_success(f"✅ Added: {new_url}")
            else:
                flash_error("URL already exists.")
        else:
            flash_error("No URL entered.")
    except Exception as e:
        flash_error(f"Add failed: {e}")
    return redirect(url_for("index"))


@app.post("/remove/<int:index>")
def remove(index):
    try:
        cfg = load_config()
        urls = cfg.get("urls", [])
        if 0 <= index < len(urls):
            removed = urls.pop(index)
            save_config(cfg)
            flash_success(f"🗑️ Removed: {removed}")
        else:
            flash_error("Invalid index.")
    except Exception as e:
        flash_error(f"Remove failed: {e}")
    return redirect(url_for("index"))

@app.post("/save")
def save():
    try:
        urls = request.form.getlist("urls")
        cycle = int(request.form.get("cycle_interval", "60"))
        idle = int(request.form.get("idle_timeout", "600"))
        cfg = {
            "urls": [u.strip() for u in urls if u.strip()],
            "cycle_interval": cycle,
            "idle_timeout": idle,
        }
        save_config(cfg)
        restart_services()
        flash_success("✅ Settings saved and services restarted.")
    except Exception as e:
        flash_error(f"Save failed: {e}")
        traceback.print_exc()
    return redirect(url_for("index"))

# --- Entry point ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
