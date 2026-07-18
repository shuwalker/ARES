#!/usr/bin/env python3
"""
ARES Safari MCP Bootstrap

Installs/configures/verifies the Safari MCP server path without relying on
computer vision. This script cannot click macOS permission prompts; it detects
which one-time grants are missing and prints the exact remediation steps.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

HOME = Path.home()
DEFAULT_SAFARI_MCP_REPO = Path(os.environ.get("ARES_SAFARI_MCP_PATH", "")).expanduser() if os.environ.get("ARES_SAFARI_MCP_PATH") else None
ARES_CONFIG = HOME / ".ares" / "config.yaml"


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 30) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip()
    except subprocess.TimeoutExpired as exc:
        if isinstance(exc.stdout, bytes):
            partial = exc.stdout.decode(errors="ignore")
        elif isinstance(exc.stdout, str):
            partial = exc.stdout
        else:
            partial = ""
        return 124, partial.strip() + "\n[TIMEOUT]"
    except FileNotFoundError:
        return 127, f"command not found: {cmd[0]}"


def check_binary(name: str) -> bool:
    return shutil.which(name) is not None


def ares_mcp_configured() -> bool:
    if not ARES_CONFIG.exists():
        return False
    text = ARES_CONFIG.read_text(errors="ignore")
    return "safari-mcp" in text and "mcp:" in text


def configure_ares() -> list[str]:
    logs: list[str] = []
    if not check_binary("ares"):
        return ["SKIP: ares CLI not found on PATH"]
    commands = [
        ["ares", "config", "set", "mcp.servers.safari-mcp.command", "npx"],
        ["ares", "config", "set", "mcp.servers.safari-mcp.args", '["safari-mcp"]'],
        ["ares", "config", "set", "mcp.servers.safari-mcp.env.SAFARI_MCP_BACKGROUND", "true"],
    ]
    for cmd in commands:
        code, out = run(cmd, timeout=20)
        logs.append(("OK" if code == 0 else "FAIL") + ": " + " ".join(cmd) + (f"\n{out}" if out else ""))
    return logs


def safari_mcp_command(repo: Path | None = None) -> tuple[list[str], Path | None, str]:
    if repo and repo.exists():
        js = repo / "index.js"
        if js.exists():
            return ["node", "index.js"], repo, f"local repo: {repo}"
    return ["npx", "-y", "safari-mcp"], None, "npx package: safari-mcp"


def probe_mcp(repo: Path | None = None) -> tuple[bool, str]:
    cmd, cwd, source = safari_mcp_command(repo)

    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "ares-safari-bootstrap", "version": "1.0.0"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "safari_doctor", "arguments": {}}},
    ]

    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None
    for req in requests:
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()

    import time

    lines: list[str] = []
    end = time.time() + 25
    while time.time() < end:
        line = proc.stdout.readline()
        if not line:
            break
        lines.append(line.rstrip())
        if '"id":2' in line:
            break

    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        proc.kill()

    out = f"source: {source}\n" + "\n".join(lines)
    ok = "Safari MCP doctor" in out or "checks passed" in out
    return ok, out


def print_report(auto_configure: bool, repo: Path | None = None) -> int:
    print("ARES Safari MCP Bootstrap")
    print("=" * 30)

    checks = []
    checks.append(("macOS", sys.platform == "darwin", "Safari MCP is macOS-only"))
    checks.append(("node", check_binary("node"), "Install Node.js 18+"))
    checks.append(("npm/npx", check_binary("npm") and check_binary("npx"), "Install npm/npx"))
    checks.append(("safari-mcp package/repo", check_binary("npx") or bool(repo and repo.exists()), "Install Node.js/npm or provide --safari-mcp-path PATH to a local safari-mcp clone"))
    checks.append(("Ares MCP config", ares_mcp_configured(), "Run with --configure-ares or add mcp.servers.safari-mcp manually"))

    for label, ok, fix in checks:
        print(("✅" if ok else "❌"), label)
        if not ok:
            print("   fix:", fix)

    if auto_configure:
        print("\nConfiguring Ares MCP entry...")
        for line in configure_ares():
            print(line)

    if repo and repo.exists() and check_binary("npm"):
        if not (repo / "node_modules").exists():
            print("\nInstalling safari-mcp dependencies...")
            code, out = run(["npm", "install"], cwd=repo, timeout=120)
            print(out)
            if code != 0:
                print("npm install failed")

    print("\nLive MCP doctor probe...")
    ok, out = probe_mcp(repo)
    print(out[-4000:] if len(out) > 4000 else out)

    print("\nOne-time macOS approvals if doctor reports failures:")
    print(textwrap.dedent("""
    1. Safari → Settings → Advanced → Show features for web developers.
    2. Safari → Develop → Allow JavaScript from Apple Events.
    3. System Settings → Privacy & Security → Automation → allow your terminal/Ares host to control Safari.
    4. For native clicks/keyboard only: System Settings → Privacy & Security → Accessibility → add safari-helper.
    5. For screenshots/PDF visual capture only: System Settings → Privacy & Security → Screen Recording → add the host app if requested.

    These approvals are one-time macOS security gates. The bootstrap can detect and guide them, but cannot click them for the user.
    """).strip())

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Configure/verify optional Safari MCP for ARES when Ares Agent is the selected backend.")
    parser.add_argument("--configure-ares", action="store_true", help="Write Ares mcp.servers.safari-mcp config using ares config set")
    parser.add_argument("--safari-mcp-path", help="Optional local path to a safari-mcp clone. If omitted, the bootstrap uses npx -y safari-mcp.")
    args = parser.parse_args()
    repo = Path(args.safari_mcp_path).expanduser() if args.safari_mcp_path else DEFAULT_SAFARI_MCP_REPO
    return print_report(args.configure_ares, repo)


if __name__ == "__main__":
    raise SystemExit(main())
