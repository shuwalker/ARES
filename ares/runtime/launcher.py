"""Hermes Agent launcher — find, install, and start Hermes.

ARES owns the runtime directory (~/.ares/). Hermes is installed there as a
git-cloned dependency. ARES writes Hermes's config and launches it as a
subprocess. The existing ~/.hermes/ installation is never modified — brain
transport copies data into ~/.ares/.hermes/ instead.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ARES_HOME = Path.home() / ".ares"
HERMES_SOURCE = ARES_HOME / "hermes-agent"
HERMES_HOME = ARES_HOME / ".hermes"  # HERMES_HOME env var points here
HERMES_GIT = "https://github.com/NousResearch/hermes-agent.git"

# The existing standalone Hermes that may already be installed.
LEGACY_HERMES = Path.home() / ".hermes" / "hermes-agent"


def find_hermes() -> Path | None:
    """Find a working Hermes install. Returns the directory containing run_agent.py.

    Checks:
    1. ~/.ares/hermes-agent/ (ARES-managed install)
    2. ~/.hermes/hermes-agent/ (legacy standalone install)
    3. 'hermes' on PATH
    """
    # ARES-managed install
    if (HERMES_SOURCE / "run_agent.py").exists():
        return HERMES_SOURCE

    # Legacy standalone install
    if (LEGACY_HERMES / "run_agent.py").exists():
        return LEGACY_HERMES

    # On PATH
    hermes_bin = shutil.which("hermes")
    if hermes_bin:
        # Resolve symlink to find the source directory
        real_path = Path(hermes_bin).resolve()
        # Typically: .../hermes-agent/venv/bin/hermes → parent is hermes-agent/
        for parent in real_path.parents:
            if (parent / "run_agent.py").exists():
                return parent

    return None


def install_hermes(target: Path | None = None) -> Path:
    """Clone and install Hermes Agent. Returns the source directory.

    If Hermes is already found, returns that path without reinstalling.
    """
    existing = find_hermes()
    if existing:
        return existing

    target = target or HERMES_SOURCE
    target.mkdir(parents=True, exist_ok=True)

    print(f"Cloning Hermes Agent into {target}...")
    subprocess.run(
        ["git", "clone", HERMES_GIT, str(target)],
        check=True,
    )

    print("Creating virtual environment...")
    subprocess.run(
        [sys.executable, "-m", "venv", str(target / "venv")],
        check=True,
    )

    pip = str(target / "venv" / "bin" / "pip")
    print("Installing Hermes dependencies...")
    subprocess.run(
        [pip, "install", "-e", str(target)],
        check=True,
    )

    print(f"Hermes installed at {target}")
    return target


def start_hermes(
    extra_args: list[str] | None = None,
    hermes_home: Path | None = None,
) -> subprocess.Popen:
    """Start Hermes as a subprocess with ARES's HERMES_HOME.

    Returns the Popen process object. Caller is responsible for lifecycle.
    """
    hermes_dir = find_hermes()
    if not hermes_dir:
        raise RuntimeError(
            "Hermes not found. Run 'ares init' first to install it."
        )

    hermes_bin = hermes_dir / "venv" / "bin" / "hermes"
    if not hermes_bin.exists():
        # Try python -m as fallback
        hermes_bin = None

    env = os.environ.copy()
    env["HERMES_HOME"] = str(hermes_home or HERMES_HOME)

    args = extra_args or []

    if hermes_bin and hermes_bin.exists():
        cmd = [str(hermes_bin)] + args
    else:
        python = str(hermes_dir / "venv" / "bin" / "python")
        cmd = [python, "-m", "hermes"] + args

    return subprocess.Popen(cmd, env=env)


def hermes_status() -> dict:
    """Check Hermes installation status. Returns a dict with details."""
    hermes_dir = find_hermes()

    result = {
        "installed": hermes_dir is not None,
        "ares_managed": hermes_dir == HERMES_SOURCE if hermes_dir else False,
        "hermes_dir": str(hermes_dir) if hermes_dir else None,
        "hermes_home": str(HERMES_HOME),
        "hermes_home_exists": HERMES_HOME.exists(),
        "hermes_home_has_config": (HERMES_HOME / "config.yaml").exists(),
        "hermes_home_has_skills": (HERMES_HOME / "skills").exists(),
        "hermes_home_has_state": (HERMES_HOME / "state").exists(),
    }

    if hermes_dir:
        venv = hermes_dir / "venv"
        result["venv_exists"] = venv.exists()
        result["run_agent_exists"] = (hermes_dir / "run_agent.py").exists()

        # Try to get version
        version_file = hermes_dir / "ares" / "__init__.py"
        if not version_file.exists():
            version_file = hermes_dir / "hermes" / "__init__.py"

    return result