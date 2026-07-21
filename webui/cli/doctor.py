#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import platform
import shutil
from pathlib import Path

class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def print_header(title):
    print(f"\n{Colors.BOLD}{Colors.YELLOW}=== {title} ==={Colors.RESET}")

def check_pass(msg):
    print(f"{Colors.GREEN}✔{Colors.RESET} {msg}")

def check_fail(msg, fix=None):
    print(f"{Colors.RED}✖{Colors.RESET} {msg}")
    if fix:
        print(f"  {Colors.YELLOW}↳ Fix: {fix}{Colors.RESET}")

def check_warn(msg, fix=None):
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {msg}")
    if fix:
        print(f"  {Colors.YELLOW}↳ Suggestion: {fix}{Colors.RESET}")

def run_diagnostics():
    print(f"{Colors.BOLD}ARES Diagnostic Tool (Doctor){Colors.RESET}")
    print("Checking system health and architecture...\n")

    # 1. System Checks
    print_header("System & Environment")
    py_ver = sys.version_info
    if py_ver.major >= 3 and py_ver.minor >= 10:
        check_pass(f"Python version {py_ver.major}.{py_ver.minor} is supported.")
    else:
        check_fail(f"Python version {py_ver.major}.{py_ver.minor} is unsupported.", "Upgrade to Python 3.10+")
    
    os_name = platform.system()
    check_pass(f"Operating System: {os_name} {platform.release()}")

    # 2. ARES Core
    print_header("ARES Core Components")
    ares_home = Path(os.path.expanduser("~/.ares"))
    install_json = ares_home / "installation.json"
    settings_json = ares_home / "webui" / "settings.json"
    
    if install_json.exists():
        check_pass("ARES installation manifest found.")
    else:
        check_fail("ARES installation manifest missing.", "Run `ares update` or reinstall.")

    # Check WebUI
    try:
        req = urllib.request.Request("http://127.0.0.1:8787/api/onboarding/status")
        with urllib.request.urlopen(req, timeout=2) as response:
            if response.status == 200:
                check_pass("ARES WebUI server is running and responding on port 8787.")
            else:
                check_warn(f"ARES WebUI responded with unexpected status code {response.status}.")
    except Exception:
        check_fail("ARES WebUI server is not responding.", "Start ARES by typing `ares start` in your terminal.")

    # 3. Network & Tailscale
    print_header("Remote Access & Networking")
    ts_ip = None
    if shutil.which("tailscale"):
        try:
            import subprocess
            out = subprocess.check_output(["tailscale", "ip", "-4"], stderr=subprocess.STDOUT, timeout=2).decode().strip()
            if out and not "Tailscale is not running" in out:
                # Filter out warning lines
                lines = [l.strip() for l in out.split("\n") if l.strip() and not l.startswith("Warning:")]
                if lines:
                    ts_ip = lines[-1]
                    check_pass(f"Tailscale is connected. Remote URL: http://{ts_ip}:8787")
                else:
                    check_warn("Could not retrieve a clean Tailscale IP.")
            else:
                check_warn("Tailscale is installed but not connected.", "Run `tailscale up` to enable remote access.")
        except Exception:
            check_warn("Could not retrieve Tailscale IP.")
    else:
        check_warn("Tailscale not found.", "Install Tailscale if you want secure remote access from your phone.")

    # 4. Backend / Framework
    print_header("Framework Orchestration")
    configured_backend = "unconfigured"
    if settings_json.exists():
        try:
            settings = json.loads(settings_json.read_text())
            configured_backend = settings.get("ares_backend", "unconfigured")
        except Exception:
            pass
            
    if configured_backend == "unconfigured":
        check_warn("No backend framework is configured yet.", "Open the ARES WebUI to complete the Framework Selection step.")
    elif configured_backend == "hermes":
        check_pass("Hermes Agent is configured as the active framework.")
        if shutil.which("hermes"):
            check_pass("Hermes CLI is available in PATH.")
        else:
            check_warn("Hermes CLI not found in PATH.", "Ensure hermes-agent was installed properly.")
            
        config_yaml = ares_home / "config.yaml"
        if config_yaml.exists():
            check_pass("Hermes configuration (config.yaml) is present.")
        else:
            check_warn("Hermes config.yaml missing.", "Complete WebUI onboarding to generate API configurations.")
    
    elif configured_backend == "jros":
        check_pass("Jaeger OS is configured as the active framework.")
        jaeger_home = Path(os.path.expanduser("~/.jaeger"))
        if jaeger_home.exists():
            check_pass("Jaeger OS home directory found (~/.jaeger).")
        else:
            check_fail("Jaeger OS home directory is missing.", "Re-run the Jaeger OS installer or complete WebUI onboarding.")
            
        # Check if JROS port 3000 is open
        try:
            req = urllib.request.Request("http://127.0.0.1:3000/api/health")
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200:
                    check_pass("Jaeger OS local server is running and healthy.")
                else:
                    check_warn("Jaeger OS server responded with non-200 status.")
        except Exception:
            check_fail("Jaeger OS local server is not responding.", "Ensure JROS daemon is running in the background.")

    print("\n" + "-"*50)
    print("Diagnostics complete. If you are experiencing issues, copy this output and provide it to support or run `ares update`.")

if __name__ == "__main__":
    run_diagnostics()
