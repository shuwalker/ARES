"""Name your Companion — ARES onboarding's call into JaegerAI's own
non-interactive instance-creation core.

JaegerAI already owns identity creation end to end: ``jaeger agent create``'s
terminal wizard and the native Jaeger app's onboarding both write through
``jaeger_ai.core.instance.setup_wizard.create_instance``, documented there as
"THE single write path for first-run setup". ARES does not re-implement any
of that — this module calls straight through to it.

Critically, that call runs as a **subprocess using JaegerAI's own venv**
(``<jaeger_home>/.venv/bin/python``), not an in-process ``sys.path`` import into
ARES's interpreter. Cross-importing ``jaeger_os`` into ARES's webui venv
reliably fails with ``ModuleNotFoundError`` (msgspec, llama-cpp-python, ...)
because ``webui/scripts/install.sh`` only ever sets up ARES's own venv —
JaegerAI's native/ML dependencies are never installed there, and never should be
(they're heavy and JaegerAI already manages them in its own venv). Running
through JaegerAI's interpreter is exactly what its ``jaeger`` launcher does, so
this reuses that same working environment instead of duplicating it.

Only the local-JaegerAI-on-this-machine path is wired here. JaegerAI has no
HTTP gateway for instance creation, so naming a Companion against a remote-only
runtime is not supported — callers get an actionable error instead of a silent
no-op.
"""
from __future__ import annotations

import json
import logging
import subprocess
import sys
from pathlib import Path
from typing import Any

from api.jros_gateway_chat import local_jros_root
from api.jros_paths import jros_instance_name

logger = logging.getLogger(__name__)

_NO_LOCAL_JROS = (
    "No local JaegerAI install was found. ARES requires JaegerAI as its Companion "
    "runtime — install it first (the onboarding step before this one), or "
    "point ARES_JAEGER_HOME/JAEGER_HOME at an existing install."
)

_DEFAULTS_SCRIPT = """
import json
from jaeger_ai.core.instance.setup_wizard import setup_defaults, _character_rows

data = setup_defaults()
data["characters"] = [
    {"id": r[0], "name": r[1], "role": r[2], "voice_id": r[3], "voice_tone": r[4]}
    for r in _character_rows()
]
print(json.dumps(data, default=str))
"""

_EXISTS_SCRIPT = """
import json, os
from jaeger_ai.core.instance.instance import default_instance_name, resolve_instance_dir

name = os.environ.get("ARES_JROS_INSTANCE") or default_instance_name()
print(json.dumps({"exists": resolve_instance_dir(name).exists()}))
"""

_CREATE_SCRIPT = """
import json, sys
from jaeger_ai.core.instance.setup_wizard import create_instance

payload = json.loads(sys.stdin.read())
try:
    layout = create_instance(
        character_id=payload["character_id"],
        name=payload.get("name"),
        display_name=payload.get("display_name"),
        personality=payload.get("personality"),
        voice_id=payload.get("voice_id"),
        permission_mode=payload.get("permission_mode") or "confirm",
        interaction_mode=payload.get("interaction_mode") or "gui",
        make_default=payload.get("make_default", True),
    )
    print(json.dumps({"ok": True, "name": layout.root.name, "instance_dir": str(layout.root)}))
except FileExistsError as exc:
    print(json.dumps({"ok": False, "error": "exists", "message": str(exc)}))
except LookupError as exc:
    print(json.dumps({"ok": False, "error": "unknown_character", "message": str(exc)}))
"""


def _jros_root() -> Path:
    root = local_jros_root()
    if root is None:
        raise RuntimeError(_NO_LOCAL_JROS)
    return root


def _jros_python(root: Path) -> Path:
    """The interpreter with JaegerAI's own dependencies installed. Falls back to
    ARES's own interpreter only if JaegerAI has no venv yet (e.g. a `--no-venv`
    install), in which case the caller's ModuleNotFoundError will be a
    more actionable signal than silently picking the wrong python."""
    candidate = root / ".venv" / "bin" / "python"
    return candidate if candidate.exists() else Path(sys.executable)


def _run_in_jros_venv(script: str, *, stdin_payload: dict[str, Any] | None = None) -> Any:
    root = _jros_root()
    python = _jros_python(root)
    import os

    env = dict(os.environ)
    instance = jros_instance_name()
    if instance:
        env["ARES_JROS_INSTANCE"] = instance
    try:
        proc = subprocess.run(
            [str(python), "-c", script],
            input=json.dumps(stdin_payload) if stdin_payload is not None else None,
            capture_output=True,
            text=True,
            cwd=str(root),
            env=env,
            timeout=60,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("JaegerAI did not respond within 60s.") from exc
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip()[-2000:] or f"JaegerAI exited with code {proc.returncode}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Unexpected JaegerAI output: {proc.stdout[:500]!r}") from exc


def companion_available() -> bool:
    """True when a local JaegerAI install is present for the naming step."""
    try:
        return local_jros_root() is not None
    except Exception:
        logger.debug("Companion availability probe failed", exc_info=True)
        return False


def install_jros_if_missing(jaeger_home: str | None = None) -> dict[str, Any]:
    """Check whether JaegerAI is installed and, if not, download and run JaegerAI's
    own installer.  Returns a status dict:

      {"installed": True, "already_present": True}  — JaegerAI already installed
      {"installed": True, "already_present": False} — JaegerAI freshly installed
      {"installed": False, "error": "..."}           — installation failed

    The installer URL and JAEGER_HOME resolution use the same env vars as
    the bash installer (JROS_INSTALL_URL, ARES_JAEGER_HOME, JAEGER_HOME).
    """
    import os
    import subprocess
    import urllib.request

    # Re-use the same detection logic as the bash installer.
    from api.jros_paths import jaeger_home as resolve_jaeger_home, jaeger_launcher

    resolved_home = Path(jaeger_home) if jaeger_home else resolve_jaeger_home()
    launcher = resolved_home / "jaeger"

    if launcher.exists() and os.access(str(launcher), os.X_OK):
        return {"installed": True, "already_present": True, "jaeger_home": str(resolved_home)}

    # JaegerAI not found — download and run its own installer.
    install_url = os.environ.get(
        "JROS_INSTALL_URL",
        "https://raw.githubusercontent.com/JenkinsRobotics/JaegerAI/master/scripts/install.sh",
    )
    env = dict(os.environ)
    env["JAEGER_HOME"] = str(resolved_home)
    env["ARES_JAEGER_HOME"] = str(resolved_home)

    try:
        logger.info("Downloading JaegerAI installer from %s", install_url)
        req = urllib.request.Request(install_url, headers={"User-Agent": "ARES-WebUI/1.0"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            script = resp.read().decode("utf-8", errors="replace")
    except Exception as exc:
        raise RuntimeError(f"Failed to download JaegerAI installer: {exc}") from exc

    try:
        result = subprocess.run(
            ["bash", "-c", script],
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("JaegerAI installer timed out after 10 minutes.")
    except Exception as exc:
        raise RuntimeError(f"Failed to run JaegerAI installer: {exc}") from exc

    if result.returncode != 0:
        stderr = (result.stderr or "").strip()[-2000:]
        raise RuntimeError(f"JaegerAI installer exited with code {result.returncode}: {stderr}")

    # Verify installation succeeded.
    if launcher.exists() and os.access(str(launcher), os.X_OK):
        return {"installed": True, "already_present": False, "jaeger_home": str(resolved_home)}
    # The installer might have used a different JAEGER_HOME; re-probe.
    from api.jros_paths import discover_jros_source_root
    found = discover_jros_source_root()
    if found is not None:
        return {"installed": True, "already_present": False, "jaeger_home": str(found)}
    raise RuntimeError(
        "JaegerAI installer completed but no launcher was found. "
        "Check the installer output and ensure JAEGER_HOME is set correctly."
    )


def companion_exists() -> bool:
    """True when a Companion instance has already been created."""
    try:
        result = _run_in_jros_venv(_EXISTS_SCRIPT)
        return bool(result.get("exists"))
    except Exception:
        logger.debug("Companion existence check failed", exc_info=True)
        return False


def companion_setup_defaults() -> dict[str, Any]:
    """Host-tier model recommendation, voices, permission modes, and the
    character roster — the same recommendations ``jaeger agent create``'s
    terminal wizard prints, served for ARES's web onboarding instead."""
    return _run_in_jros_venv(_DEFAULTS_SCRIPT)


def list_characters() -> list[dict[str, str]]:
    """Characters available to play the Companion (id, name, role, voice)."""
    return companion_setup_defaults().get("characters", [])


def create_companion(
    *,
    character_id: str,
    name: str | None = None,
    display_name: str | None = None,
    personality: str | None = None,
    voice_id: str | None = None,
    permission_mode: str = "confirm",
    make_default: bool = True,
) -> dict[str, Any]:
    """Name and create the Companion by calling straight through to JROS's
    own ``create_instance`` (run inside JROS's venv — see module docstring).
    Raises ``ValueError`` with a user-facing message for the two expected
    failure modes (unknown character, name already taken); anything else
    propagates as a ``RuntimeError``."""
    if not str(character_id or "").strip():
        raise ValueError("character_id is required")

    result = _run_in_jros_venv(
        _CREATE_SCRIPT,
        stdin_payload={
            "character_id": character_id,
            "name": name,
            "display_name": display_name,
            "personality": personality,
            "voice_id": voice_id,
            "permission_mode": permission_mode,
            "interaction_mode": "gui",
            "make_default": make_default,
        },
    )
    if not result.get("ok"):
        message = str(result.get("message") or "Could not create the Companion.")
        if result.get("error") == "exists":
            raise ValueError(f"A Companion named {name!r} already exists. Pick a different name.")
        raise ValueError(message)
    return result
