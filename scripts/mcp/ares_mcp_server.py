#!/usr/bin/env python3
"""
ARES-Mac MCP Server — runs on Mac Studio, exposes tools to ARES v1 (RackPC).

Transport: StreamableHTTP on 0.0.0.0:9501
Reachable from: LAN (10.15.0.9:9501) and Tailscale (100.74.2.15:9501)
"""

import json
import os
import subprocess
import datetime
import platform
import socket
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    name="ARES-Mac Studio",
    instructions="Mac Studio twin — robotics, video, hardware. Exposes tools to ARES v1.",
    host="0.0.0.0",
    port=9501,
)

NAS_ROOT = "/Volumes/Jenkins_Robotics"
ARES_BRAIN = f"{NAS_ROOT}/ARES_Brain"
LOCAL_FALLBACK = os.path.expanduser("~/ARES_Brain_local")
RELAY_LOG = os.path.expanduser("~/ares_relay.log")
HERMES_CONFIG = os.path.expanduser("~/.hermes/config.yaml")

def _now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def _shell(cmd, timeout=30):
    """Run a shell command safely."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return {"stdout": r.stdout.strip()[:8000], "stderr": r.stderr.strip()[:2000], "exit_code": r.returncode}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Command timed out after {timeout}s", "exit_code": 124}

def _nas_ok():
    """Check if NAS is mounted and readable."""
    return os.path.ismount(NAS_ROOT) and os.path.isdir(ARES_BRAIN)

def _read_path(path, encoding="utf-8"):
    """Read a file, with local fallback."""
    if not os.path.exists(path):
        # Try local fallback
        rel = os.path.relpath(path, ARES_BRAIN) if path.startswith(ARES_BRAIN) else None
        if rel:
            local_path = os.path.join(LOCAL_FALLBACK, rel)
            if os.path.exists(local_path):
                path = local_path
            else:
                return {"error": f"File not found: {path} (also checked local: {local_path})"}
        else:
            return {"error": f"File not found: {path}"}

    try:
        with open(path, "r", encoding=encoding) as f:
            content = f.read()
        return {"content": content, "path": path, "size": len(content)}
    except Exception as e:
        return {"error": str(e), "path": path}

def _write_path(path, content):
    """Write a file, with local fallback."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        return {"status": "written", "path": path, "size": len(content)}
    except PermissionError:
        # Try local fallback
        if path.startswith(NAS_ROOT):
            rel = path[len(NAS_ROOT):].lstrip("/")
            local_path = os.path.join(LOCAL_FALLBACK, rel)
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            with open(local_path, "w") as f:
                f.write(content)
            return {"status": "written_to_local_fallback", "path": local_path, "size": len(content)}
        return {"error": f"Permission denied: {path}"}
    except Exception as e:
        return {"error": str(e), "path": path}


# ─── Tools ───────────────────────────────────────────────────────────────────

@mcp.tool()
def ping() -> dict:
    """Basic health check. Returns machine identity + status."""
    return {
        "machine": "ARES-Mac Studio",
        "user": os.environ.get("USER", "unknown"),
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "tailscale_ip": "100.74.2.15",
        "lan_ip": "10.15.0.9",
        "time": _now(),
        "nas_mounted": _nas_ok(),
        "relay_alive": os.path.exists(RELAY_LOG),
        "uptime": _shell("uptime")["stdout"],
    }


@mcp.tool()
def get_status() -> dict:
    """Full infrastructure status: NAS, relay, gateway, MCP, tunnels."""
    status = {
        "time": _now(),
        "nas": {
            "mounted": _nas_ok(),
            "path": NAS_ROOT,
            "df": _shell(f"df -h {NAS_ROOT} 2>/dev/null | tail -1")["stdout"] if _nas_ok() else "UNMOUNTED",
        },
        "relay": {
            "port_9500": bool(_shell("lsof -i :9500 2>/dev/null").get("stdout")),
            "log_tail": _shell(f"tail -5 {RELAY_LOG} 2>/dev/null")["stdout"] if os.path.exists(RELAY_LOG) else "NO LOG",
        },
        "gateway": {
            "port_8644": _shell("curl -s -o /dev/null -w '%{http_code}' http://localhost:8644/health 2>/dev/null")["stdout"],
        },
        "tunnels": {
            "v1_9100": _shell("nc -z -w 1 localhost 9100 2>&1; echo $?")["stdout"],
            "v1_9101": _shell("nc -z -w 1 localhost 9101 2>&1; echo $?")["stdout"],
        },
        "tailscale": {
            "rackpc_ping": _shell("tailscale ping -c 1 rackpc001 2>&1 | tail -1")["stdout"],
        },
        "processes": {
            "hermes_agent": bool(_shell("pgrep -f hermes-cli 2>/dev/null").get("stdout")),
        },
    }
    return status


@mcp.tool()
def read_nas(path: str) -> dict:
    """Read a file from the NAS. Path relative to /Volumes/Jenkins_Robotics/ARES_Brain/ or absolute."""
    if not path.startswith("/"):
        full_path = os.path.join(ARES_BRAIN, path)
    else:
        full_path = path
    return _read_path(full_path)


@mcp.tool()
def write_nas(path: str, content: str) -> dict:
    """Write a file to the NAS. Path relative to /Volumes/Jenkins_Robotics/ARES_Brain/ or absolute."""
    if not path.startswith("/"):
        full_path = os.path.join(ARES_BRAIN, path)
    else:
        full_path = path
    result = _write_path(full_path, content)
    result["time"] = _now()
    return result


@mcp.tool()
def list_nas(directory: str = ".") -> dict:
    """List files in a NAS directory under ARES_Brain."""
    if directory == ".":
        full_dir = ARES_BRAIN
    elif directory.startswith("/"):
        full_dir = directory
    else:
        full_dir = os.path.join(ARES_BRAIN, directory)

    try:
        entries = []
        for entry in sorted(os.listdir(full_dir)):
            epath = os.path.join(full_dir, entry)
            st = os.stat(epath)
            entries.append({
                "name": entry,
                "type": "dir" if os.path.isdir(epath) else "file",
                "size": st.st_size if os.path.isfile(epath) else 0,
                "mtime": datetime.datetime.fromtimestamp(st.st_mtime).isoformat(),
            })
        return {"directory": full_dir, "entries": entries, "count": len(entries)}
    except Exception as e:
        return {"error": str(e), "directory": full_dir}


@mcp.tool()
def exec_local(command: str, timeout: int = 30) -> dict:
    """Execute a shell command on Mac Studio. Returns stdout, stderr, exit_code."""
    return _shell(command, timeout=timeout)


@mcp.tool()
def relay_message(message: str, target: str = "v1") -> dict:
    """Send a message through the relay (port 9500) to ARES v1 or broadcast."""
    msg = json.dumps({"from": "ARES-Mac", "message": message, "time": _now()})
    if target == "v1":
        # Try Tailscale
        r = _shell(f"printf '{msg}\\n' | nc -w 2 100.85.249.11 9500 2>/dev/null", timeout=5)
        if r.get("stdout"):
            return {"status": "sent_via_tailscale", "response": r["stdout"]}
        # Fallback: LAN
        r2 = _shell(f"printf '{msg}\\n' | nc -w 2 10.15.0.239 9500 2>/dev/null", timeout=5)
        if r2.get("stdout"):
            return {"status": "sent_via_lan", "response": r2["stdout"]}
        return {"status": "no_response", "tried": ["tailscale", "lan"]}
    else:
        return {"error": f"Unknown target: {target}"}


@mcp.tool()
def write_handoff(message: str, priority: str = "normal") -> dict:
    """Write a handoff message to the NAS for ARES v1 to pick up on next cycle."""
    entry = {
        "from": "ARES-Mac",
        "time": _now(),
        "priority": priority,
        "message": message,
    }
    handoff_path = f"{ARES_BRAIN}/handoff_from_hermes.json"
    return _write_path(handoff_path, json.dumps(entry, indent=2))


@mcp.tool()
def twin_state_update(updates: dict) -> dict:
    """Update the shared twin_state.json on NAS."""
    state_path = f"{ARES_BRAIN}/twin_state.json"
    
    # Read existing
    existing = {}
    read_result = _read_path(state_path)
    if "content" in read_result:
        try:
            existing = json.loads(read_result["content"])
        except json.JSONDecodeError:
            existing = {}

    # Merge updates
    existing.update(updates)
    existing["last_updated_by"] = "ARES-Mac"
    existing["last_updated_at"] = _now()

    return _write_path(state_path, json.dumps(existing, indent=2))


@mcp.tool()
def get_skills_list() -> dict:
    """Return the list of skills installed on Mac Studio (with descriptions)."""
    skills_dir = os.path.expanduser("~/.hermes/skills")
    skills = []
    try:
        for root, dirs, files in os.walk(skills_dir):
            if "SKILL.md" in files:
                skill_path = os.path.join(root, "SKILL.md")
                try:
                    with open(skill_path) as f:
                        content = f.read()
                    # Extract name from frontmatter or directory
                    name = os.path.basename(root)
                    # Extract description from frontmatter
                    desc = ""
                    for line in content.split("\n"):
                        if line.startswith("description:"):
                            desc = line.split(":", 1)[1].strip().strip('"').strip("'")
                            break
                    skills.append({"name": name, "description": desc, "path": skill_path})
                except:
                    pass
    except Exception as e:
        return {"error": str(e)}
    return {"skills": sorted(skills, key=lambda s: s["name"]), "count": len(skills)}


@mcp.tool()
def get_memory() -> dict:
    """Return Hermes memory entries (user profile and agent memory)."""
    # Read memory from ~/.hermes/memory/ or wherever Hermes stores it
    # This reads the context injected at session start
    memory_file = os.path.expanduser("~/.hermes/memory.json")
    if os.path.exists(memory_file):
        return _read_path(memory_file)
    return {"error": "memory.json not found", "note": "Memory is injected into session context"}


@mcp.tool()
def get_config_snapshot() -> dict:
    """Return a snapshot of Hermes config (redacted credentials)."""
    result = _read_path(HERMES_CONFIG)
    if "content" not in result:
        return result

    content = result["content"]
    # Redact sensitive values
    lines = content.split("\n")
    redacted_lines = []
    for line in lines:
        stripped = line.strip()
        if any(k in stripped.lower() for k in ["secret:", "key:", "token:", "password:", "api_key"]):
            # Keep the key, redact the value
            parts = line.split(":", 1)
            if len(parts) == 2:
                redacted_lines.append(f"{parts[0]}: [REDACTED]")
            else:
                redacted_lines.append(line)
        else:
            redacted_lines.append(line)
    
    return {"content": "\n".join(redacted_lines), "path": HERMES_CONFIG, "redacted": True}


if __name__ == "__main__":
    print(f"ARES-Mac MCP Server starting on 0.0.0.0:9501")
    print(f"  LAN:     http://10.15.0.9:9501/mcp")
    print(f"  Tailscale: http://100.74.2.15:9501/mcp")
    print(f"  NAS:     {NAS_ROOT} (mounted: {_nas_ok()})")
    print(f"  Tools:   {len([t for t in dir(mcp) if not t.startswith('_')])} exposed")
    mcp.run(transport="streamable-http")
