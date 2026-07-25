#!/usr/bin/env python3
"""ARES MCP Bootstrap

Configures and verifies MCP servers for an ARES deployment.

Ares Agent is the default backend today, but this tool keeps the public
onboarding language backend-neutral: configure the selected user's backend and
only use Ares-specific commands when `--backend ares` is selected.

Design rule:
- Hardware/app-bound MCPs run locally on the machine that owns the app/device.
- Containerizable/API/database MCPs can run on a trusted server/homelab/VPS/NAS
  and be exposed over authenticated private-network HTTP.

The script is intentionally conservative: it configures known-safe local servers,
prints remote deployment plans, and verifies what is reachable.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path.home()
ARES_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class MCPServerSpec:
    name: str
    mode: str  # local-only, local-or-remote, remote-preferred
    reason: str
    command: str | None = None
    args: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)
    url_env: str | None = None
    verify_command: list[str] | None = None
    install_hint: str = ""
    remote_hint: str = ""


KNOWN_SERVERS: dict[str, MCPServerSpec] = {
    "safari-mcp": MCPServerSpec(
        name="safari-mcp",
        mode="local-only",
        reason="Requires the real macOS Safari app, AppleScript, and bundled Swift helper on the same Mac.",
        command="npx",
        args=["safari-mcp"],
        env={"SAFARI_MCP_BACKGROUND": "true"},
        verify_command=["python3", str(ARES_ROOT / "tools" / "safari-mcp-bootstrap" / "safari_mcp_bootstrap.py")],
        install_hint="Install Node 18+ and run the Safari bootstrap on the macOS machine that owns Safari. Package source: https://github.com/achiya-automation/safari-mcp",
        remote_hint="Do not run on Linux/Windows servers. Register locally in the selected backend on the Mac that owns Safari.",
    ),
    "filesystem": MCPServerSpec(
        name="filesystem",
        mode="local-or-remote",
        reason="Can expose a chosen directory over stdio locally or via an HTTP MCP gateway on a server.",
        command="npx",
        args=["-y", "@modelcontextprotocol/server-filesystem", str(ARES_ROOT)],
        install_hint="Requires Node/npm. Restrict exposed paths to the exact workspace directory.",
        remote_hint="Good remote candidate if the files live on that server/NAS; expose over private-network HTTP with auth.",
    ),
    "time": MCPServerSpec(
        name="time",
        mode="remote-preferred",
        reason="Stateless utility server; no reason to spend Mac GUI resources.",
        command="uvx",
        args=["mcp-server-time"],
        install_hint="Requires uv/uvx on the host running it.",
        remote_hint="Good remote candidate; can run as a small service and be consumed over HTTP if wrapped by an MCP HTTP gateway.",
    ),
}


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 60) -> tuple[int, str]:
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


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def ares_set(key: str, value: str) -> tuple[int, str]:
    return run(["ares", "config", "set", key, value], timeout=30)


def backend_missing_hint(backend: str) -> str:
    if backend == "ares":
        return (
            "Ares Agent backend not found. Install it with:\n"
            "curl -fsSL https://raw.githubusercontent.com/NousResearch/ares-agent/main/scripts/install.sh | bash\n"
            "Then run: ares setup && ares doctor\n"
            "Docs: https://ares-agent.nousresearch.com/docs"
        )
    return f"Backend '{backend}' is not configured by this bootstrap yet. Connect an existing backend URL or install Ares Agent."


def configure_local(spec: MCPServerSpec, backend: str = "ares") -> list[str]:
    logs: list[str] = []
    if backend != "ares":
        return [backend_missing_hint(backend)]
    if not have("ares"):
        return ["FAIL: " + backend_missing_hint("ares")]
    if not spec.command:
        return [f"SKIP: {spec.name} has no local command; configure URL instead"]

    commands: list[tuple[str, str]] = [
        (f"mcp.servers.{spec.name}.command", spec.command),
        (f"mcp.servers.{spec.name}.args", json.dumps(spec.args)),
    ]
    for k, v in commands:
        code, out = ares_set(k, v)
        logs.append(("OK" if code == 0 else "FAIL") + f": {k} = {v}" + (f"\n{out}" if out else ""))
    for env_key, env_val in spec.env.items():
        code, out = ares_set(f"mcp.servers.{spec.name}.env.{env_key}", env_val)
        logs.append(("OK" if code == 0 else "FAIL") + f": env {env_key} = {env_val}" + (f"\n{out}" if out else ""))
    return logs


def configure_remote(name: str, url: str, headers_json: str | None = None, backend: str = "ares") -> list[str]:
    logs: list[str] = []
    if backend != "ares":
        return [backend_missing_hint(backend), f"Remote MCP URL to add manually: {name} -> {url}"]
    if not have("ares"):
        return ["FAIL: " + backend_missing_hint("ares")]
    code, out = ares_set(f"mcp.servers.{name}.url", url)
    logs.append(("OK" if code == 0 else "FAIL") + f": mcp.servers.{name}.url = {url}" + (f"\n{out}" if out else ""))
    if headers_json:
        try:
            headers = json.loads(headers_json)
        except json.JSONDecodeError as exc:
            return logs + [f"FAIL: invalid headers JSON: {exc}"]
        for k, v in headers.items():
            code, out = ares_set(f"mcp.servers.{name}.headers.{k}", str(v))
            logs.append(("OK" if code == 0 else "FAIL") + f": header {k}" + (f"\n{out}" if out else ""))
    return logs


def verify(spec: MCPServerSpec) -> tuple[bool, str]:
    if spec.verify_command:
        code, out = run(spec.verify_command, timeout=90)
        return code == 0, out
    if spec.command and not have(spec.command):
        return False, f"Missing command: {spec.command}. {spec.install_hint}"
    return True, "Static verification only: command present/configurable. Restart Ares and run `ares mcp list` / `ares mcp test NAME` if available."


def print_catalog(backend: str = "ares") -> None:
    print("ARES MCP Server Catalog")
    print("=" * 24)
    print(f"Backend: {backend}")
    if backend == "ares" and not have("ares"):
        print("\n" + backend_missing_hint("ares"))
    for spec in KNOWN_SERVERS.values():
        print(f"\n{spec.name}")
        print(f"  mode: {spec.mode}")
        print(f"  why: {spec.reason}")
        print(f"  local: {spec.command or '-'} {' '.join(spec.args)}")
        print(f"  install: {spec.install_hint}")
        print(f"  remote: {spec.remote_hint}")


def print_plan(backend: str = "ares") -> None:
    print("ARES MCP Deployment Plan")
    print("=" * 24)
    print(f"ARES repo: {ARES_ROOT}")
    print(f"Backend: {backend}")
    print("\nLocal/app-bound MCPs:")
    for spec in KNOWN_SERVERS.values():
        if spec.mode == "local-only":
            print(f"- {spec.name}: {spec.reason}")
    print("\nRemote/server MCPs:")
    for spec in KNOWN_SERVERS.values():
        if spec.mode != "local-only":
            print(f"- {spec.name}: {spec.remote_hint}")
    print("\nRule: configure local-only servers as stdio in the selected backend on the owning machine; configure remote servers by authenticated private-network URL.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Configure and verify ARES MCP servers for the selected backend.")
    parser.add_argument("--backend", default="ares", help="Agent backend to configure. Default: ares. Non-Ares backends print manual guidance for now.")
    parser.add_argument("--catalog", action="store_true", help="Print known MCP server catalog")
    parser.add_argument("--plan", action="store_true", help="Print local vs remote/server deployment plan")
    parser.add_argument("--configure-local", choices=sorted(KNOWN_SERVERS), help="Configure a known local MCP server in the selected backend")
    parser.add_argument("--configure-remote", metavar="NAME", help="Configure an HTTP/remote MCP server in the selected backend")
    parser.add_argument("--url", help="Remote MCP URL for --configure-remote")
    parser.add_argument("--headers-json", help="Optional JSON headers for --configure-remote")
    parser.add_argument("--verify", choices=sorted(KNOWN_SERVERS), help="Verify a known MCP server")
    parser.add_argument("--all", action="store_true", help="Print catalog, plan, configure safari-mcp locally, and verify it")
    args = parser.parse_args()

    if args.catalog or args.all:
        print_catalog(args.backend)
        print()
    if args.plan or args.all:
        print_plan(args.backend)
        print()
    if args.configure_local or args.all:
        name = args.configure_local or "safari-mcp"
        spec = KNOWN_SERVERS[name]
        print(f"Configuring local MCP server: {name}")
        for line in configure_local(spec, args.backend):
            print(line)
        print()
    if args.configure_remote:
        if not args.url:
            print("--url is required with --configure-remote", file=sys.stderr)
            return 2
        print(f"Configuring remote MCP server: {args.configure_remote}")
        for line in configure_remote(args.configure_remote, args.url, args.headers_json, args.backend):
            print(line)
        print()
    if args.verify or args.all:
        name = args.verify or "safari-mcp"
        spec = KNOWN_SERVERS[name]
        ok, out = verify(spec)
        print(f"Verification for {name}: {'PASS' if ok else 'FAIL'}")
        print(out[-6000:] if len(out) > 6000 else out)
        return 0 if ok else 1

    if not any([args.catalog, args.plan, args.configure_local, args.configure_remote, args.verify, args.all]):
        parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
