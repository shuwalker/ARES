#!/usr/bin/env python3
"""ARES Deck — Quick Action Panel for Steam Deck
Serves a button grid UI. Each button executes a script/action on the Mac Studio.
"""

import os
import sys
import json
import subprocess
import shutil
from pathlib import Path
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS

APP_DIR = os.path.dirname(os.path.abspath(__file__))
ARES_DESKTOP = os.path.dirname(APP_DIR)
ARES_APP = "/Applications/ARES.app/Contents/MacOS/ARES"

cmd = lambda c: ["/bin/bash", "-lc", c]

def run_shell(script, cwd=None, timeout=120):
    """Run a shell script, capture stdout/stderr."""
    try:
        result = subprocess.run(
            cmd(script),
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd
        )
        return {
            "success": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "returncode": -1, "stdout": "", "stderr": "Timed out"}
    except Exception as e:
        return {"success": False, "returncode": -1, "stdout": "", "stderr": str(e)}

# ── Command handlers ────────────────────────────────────────

def swift_build_debug():
    return run_shell(f"cd {shell_quote(ARES_DESKTOP)} && swift build", timeout=120)

def swift_build_release():
    return run_shell(f"cd {shell_quote(ARES_DESKTOP)} && swift build -c release", timeout=300)

def deploy_ares():
    src = os.path.join(ARES_DESKTOP, ".build", "arm64-apple-macosx", "release", "ARES")
    if not os.path.exists(src):
        return {"success": False, "stderr": f"No release binary at {src}. Build release first."}
    backup = ARES_APP + ".bak"
    if os.path.exists(ARES_APP):
        shutil.copy2(ARES_APP, backup)
    shutil.copy2(src, ARES_APP)
    # Kill old
    subprocess.run(["pkill", "-f", ARES_APP], capture_output=True)
    # Launch new
    subprocess.Popen(["nohup", ARES_APP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"success": True, "stdout": "Deployed and relaunched."}

def start_hermes():
    return run_shell("hermes gateway start || python3 -m hermes_gateway", timeout=10)

def kill_hermes():
    r = run_shell("pkill -f 'hermes.*gateway' || pkill -f 'python3.*9119' || true")
    r["stdout"] = "Hermes gateway killed (if running)."
    return r

def kill_ares():
    r = run_shell(f"pkill -f {shell_quote(ARES_APP)} || true")
    r["stdout"] = "ARES app killed."
    return r

def relaunch_ares():
    run_shell(f"pkill -f {shell_quote(ARES_APP)} || true")
    subprocess.Popen(["nohup", ARES_APP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"success": True, "stdout": "ARES relaunched."}

def health_check():
    lines = []
    for port, name in [(9119, "Gateway"), (8642, "API"), (8765, "Deck")]:
        r = run_shell(f"lsof -i :{port} | grep LISTEN || echo 'NOT LISTENING'", timeout=5)
        status = "UP" if "LISTEN" in r["stdout"] else "DOWN"
        lines.append(f"{name} :{port} → {status}")
    return {"success": True, "stdout": "\n".join(lines)}

def git_status():
    return run_shell(f"cd {shell_quote(ARES_DESKTOP)} && git status --short && echo '---' && git log --oneline -3", timeout=10)

def clean_build():
    return run_shell(f"cd {shell_quote(ARES_DESKTOP)} && rm -rf .build/debug .build/release && swift package clean", timeout=30)

def tail_logs():
    # Last 50 lines of unified log for ARES
    r = run_shell("log show --predicate 'process == \"ARES\"' --last 1h | tail -n 50", timeout=15)
    if not r["stdout"]:
        r = run_shell("log stream --predicate 'process == \"ARES\"' --level debug --timeout 5s || echo 'No recent ARES logs'", timeout=10)
    return r

def disk_space():
    return run_shell("df -h / && echo '---' && du -sh ~/GitHub/ARES-Autonomous-Reasoning-Execution-System/ 2>/dev/null", timeout=5)

COMMANDS = {
    "swift_build_debug": swift_build_debug,
    "swift_build_release": swift_build_release,
    "deploy_ares": deploy_ares,
    "start_hermes": start_hermes,
    "kill_hermes": kill_hermes,
    "kill_ares": kill_ares,
    "relaunch_ares": relaunch_ares,
    "health_check": health_check,
    "git_status": git_status,
    "clean_build": clean_build,
    "tail_logs": tail_logs,
    "disk_space": disk_space,
}

def shell_quote(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"

# ── Flask app ───────────────────────────────────────────────

app = Flask(__name__, static_folder=APP_DIR)
CORS(app)

@app.route("/")
def index():
    return send_from_directory(APP_DIR, "index.html")

@app.route("/execute", methods=["POST"])
def execute():
    data = request.get_json(force=True)
    cmd_name = data.get("command", "")
    handler = COMMANDS.get(cmd_name)
    if not handler:
        return jsonify({"success": False, "stderr": f"Unknown command: {cmd_name}"}), 400
    result = handler()
    return jsonify(result)

@app.route("/api/status")
def api_status():
    return jsonify({
        "hermes_gateway": False,
        "api_server": False,
        "version": "deck-1.0"
    })

if __name__ == "__main__":
    print("ARES Deck starting on http://0.0.0.0:8765")
    app.run(host="0.0.0.0", port=8765, debug=False, threaded=True)
