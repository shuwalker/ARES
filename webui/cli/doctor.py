#!/usr/bin/env python3
"""ARES doctor — system + peer-runtime health checks.

Companion (JaegerAI) is a required peer product, not an in-process library.
This tool probes ARES itself and delegates readiness to Jaeger's own
``jaeger doctor`` when available.
"""
from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path


class Colors:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def print_header(title: str) -> None:
    print(f"\n{Colors.BOLD}{Colors.YELLOW}=== {title} ==={Colors.RESET}")


def check_pass(msg: str) -> None:
    print(f"{Colors.GREEN}✔{Colors.RESET} {msg}")


def check_fail(msg: str, fix: str | None = None) -> None:
    print(f"{Colors.RED}✖{Colors.RESET} {msg}")
    if fix:
        print(f"  {Colors.YELLOW}↳ Fix: {fix}{Colors.RESET}")


def check_warn(msg: str, fix: str | None = None) -> None:
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {msg}")
    if fix:
        print(f"  {Colors.YELLOW}↳ Suggestion: {fix}{Colors.RESET}")


def _http_ok(url: str, timeout: float = 2.0) -> tuple[bool, int | None]:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ARES-Doctor/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return True, response.status
    except Exception:
        return False, None


def resolve_jaeger_home() -> Path:
    raw = (
        os.environ.get("ARES_JAEGER_HOME")
        or os.environ.get("JAEGER_HOME")
        or str(Path.home() / "jaeger")
    )
    return Path(os.path.expandvars(raw)).expanduser().resolve()


def find_webui_python(ares_home: Path, ares_src: Path | None) -> Path | None:
    candidates = [
        ares_home / "webui" / "venv" / "bin" / "python",
        ares_home / "webui" / ".venv" / "bin" / "python",
    ]
    if ares_src is not None:
        candidates.extend(
            [
                ares_src / "webui" / "venv" / "bin" / "python",
                ares_src / "webui" / ".venv" / "bin" / "python",
            ]
        )
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return path
    return None


def probe_jaeger(jaeger_home: Path) -> None:
    print_header("Companion Runtime (JaegerAI peer)")

    launcher = jaeger_home / "jaeger"
    venv_py = jaeger_home / ".venv" / "bin" / "python"

    if launcher.is_file() and os.access(launcher, os.X_OK):
        check_pass(f"JaegerAI launcher found: {launcher}")
    else:
        check_fail(
            f"JaegerAI launcher missing at {launcher}",
            "Install peer: curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh | bash",
        )
        return

    if venv_py.is_file():
        check_pass(f"JaegerAI venv present: {venv_py}")
    else:
        check_warn(
            "JaegerAI .venv not found",
            f"cd {jaeger_home} && ./install.sh",
        )

    instances_root = jaeger_home / ".jaeger_os" / "instances"
    # Some installs keep a pointer file rather than dirs until first agent create.
    active_ptr = jaeger_home / ".jaeger_os" / "active_instance"
    if instances_root.is_dir():
        instances = [p.name for p in instances_root.iterdir() if p.is_dir()]
        if instances:
            check_pass(f"Companion instance(s): {', '.join(sorted(instances))}")
        elif active_ptr.is_file():
            check_warn(
                f"active_instance set ({active_ptr.read_text(encoding='utf-8', errors='replace').strip()!r}) but no instance dirs yet",
                "Complete ARES onboarding or run: jaeger agent create",
            )
        else:
            check_warn(
                "No Companion instances yet",
                "Complete ARES onboarding or run: jaeger agent create",
            )
    else:
        check_warn(
            "No .jaeger_os/instances directory",
            "Run Jaeger install, then create an agent via ARES onboarding",
        )

    # Prefer Jaeger's own doctor when available (machine-readable when possible).
    try:
        result = subprocess.run(
            [str(launcher), "doctor", "--doctor-check"],
            capture_output=True,
            text=True,
            timeout=90,
            cwd=str(jaeger_home),
        )
        if result.returncode == 0:
            check_pass("jaeger doctor --doctor-check: OK")
        else:
            tail = (result.stdout or result.stderr or "").strip().splitlines()
            detail = tail[-1] if tail else f"exit {result.returncode}"
            check_warn(
                f"jaeger doctor reported issues ({detail})",
                f"Run: {launcher} doctor",
            )
    except FileNotFoundError:
        check_warn("Could not execute jaeger doctor", "Ensure the launcher is executable")
    except subprocess.TimeoutExpired:
        check_warn("jaeger doctor timed out", "Run manually: jaeger doctor")
    except Exception as exc:
        check_warn(f"jaeger doctor failed: {exc}")

    # Gateway health (default ARES jros URL)
    ok, status = _http_ok("http://127.0.0.1:8643/v1/health", timeout=1.5)
    if ok:
        check_pass(f"Jaeger gateway healthy on :8643 (HTTP {status})")
    else:
        check_warn(
            "Jaeger gateway not responding on 127.0.0.1:8643",
            "Start with: jaeger gateway   (or let ARES onboarding/WebUI start it)",
        )


def run_diagnostics() -> None:
    print(f"{Colors.BOLD}ARES Diagnostic Tool (Doctor){Colors.RESET}")
    print("Checking system health and peer runtimes...\n")

    print_header("System & Environment")
    py_ver = sys.version_info
    if py_ver.major >= 3 and py_ver.minor >= 10:
        check_pass(f"Python version {py_ver.major}.{py_ver.minor} is supported.")
    else:
        check_fail(
            f"Python version {py_ver.major}.{py_ver.minor} is unsupported.",
            "Upgrade to Python 3.10+",
        )

    os_name = platform.system()
    check_pass(f"Operating System: {os_name} {platform.release()}")

    print_header("ARES Core Components")
    ares_home = Path(os.path.expanduser("~/.ares")).resolve()
    install_json = ares_home / "installation.json"
    # settings may live under install home or symlink target webui/
    settings_candidates = [
        ares_home / "webui" / "settings.json",
        ares_home / "settings.json",
    ]

    if install_json.exists():
        check_pass(f"ARES installation manifest found ({install_json})")
        try:
            manifest = json.loads(install_json.read_text(encoding="utf-8"))
            src = manifest.get("source_dir")
            if src:
                check_pass(f"Source dir: {src}")
        except Exception:
            check_warn("installation.json present but not valid JSON")
    else:
        check_fail(
            "ARES installation manifest missing.",
            "Run bash install.sh from the ARES checkout",
        )

    ares_src = None
    if install_json.exists():
        try:
            ares_src = Path(json.loads(install_json.read_text()).get("source_dir", ""))
            if not ares_src.exists():
                ares_src = None
        except Exception:
            ares_src = None

    webui_py = find_webui_python(ares_home, ares_src)
    if webui_py:
        check_pass(f"WebUI Python: {webui_py}")
    else:
        check_fail(
            "WebUI virtualenv python not found",
            "Re-run: bash install.sh --role primary",
        )

    ok, status = _http_ok("http://127.0.0.1:8787/health")
    if not ok:
        ok, status = _http_ok("http://127.0.0.1:8787/api/onboarding/status")
    if ok:
        check_pass(f"ARES WebUI responding on port 8787 (HTTP {status})")
    else:
        check_fail(
            "ARES WebUI server is not responding on 8787.",
            "Start with: ares start   or open ARES.app",
        )

    print_header("Remote Access & Networking")
    if shutil.which("tailscale"):
        try:
            out = subprocess.check_output(
                ["tailscale", "ip", "-4"],
                stderr=subprocess.STDOUT,
                timeout=2,
            ).decode()
            lines = [
                line.strip()
                for line in out.splitlines()
                if line.strip() and not line.startswith("Warning:")
            ]
            if lines:
                check_pass(f"Tailscale connected. Remote URL: http://{lines[-1]}:8787")
            else:
                check_warn(
                    "Tailscale installed but no IP",
                    "Run `tailscale up` to enable remote access.",
                )
        except Exception:
            check_warn(
                "Could not query Tailscale",
                "Run `tailscale up` if you want remote access.",
            )
    else:
        check_warn(
            "Tailscale not found (optional).",
            "Install from https://tailscale.com/download for phone/remote access.",
        )

    print_header("Framework Orchestration")
    configured_backend = "unconfigured"
    for settings_json in settings_candidates:
        if settings_json.exists():
            try:
                settings = json.loads(settings_json.read_text(encoding="utf-8"))
                configured_backend = settings.get("ares_backend", "unconfigured")
                check_pass(f"settings.json: {settings_json} (backend={configured_backend})")
                break
            except Exception:
                check_warn(f"Could not parse {settings_json}")
    else:
        check_warn("No WebUI settings.json found yet (fresh install is OK)")

    if configured_backend == "unconfigured":
        check_warn(
            "No backend framework configured yet.",
            "Complete ARES onboarding (Companion = JaegerAI).",
        )
    elif configured_backend in ("jros", "jaeger", "hybrid"):
        check_pass(f"Backend configured: {configured_backend}")
    elif configured_backend == "hermes":
        check_pass("Hermes Agent is configured as the active framework.")
        if shutil.which("hermes"):
            check_pass("Hermes CLI is available in PATH.")
        else:
            check_warn("Hermes CLI not found in PATH.")

    probe_jaeger(resolve_jaeger_home())

    print("\n" + "-" * 50)
    print(
        "Diagnostics complete. Fix ✖ items first, then re-run `ares doctor`. "
        "Companion setup issues usually need `jaeger doctor` or ARES onboarding."
    )


if __name__ == "__main__":
    run_diagnostics()
