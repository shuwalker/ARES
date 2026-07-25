"""Regression tests for the #4449 state-dir contract folded into #4454.

`api.config.STATE_DIR` is a module-level global computed from the environment at
import time. Exercising how it's derived requires importing config under a
specific ARES_HOME / ARES_WEBUI_STATE_DIR. We do this in a SUBPROCESS rather
than `importlib.reload(config)` in-process: reloading config inside the shared
pytest process leaks recomputed globals (STATE_DIR/SESSION_DIR) and stale
references into later tests (the cancel/stream/health/state-isolation suites),
which is fragile no matter how carefully env is restored. A subprocess gives a
truly isolated import and can't pollute the test process.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

_PROBE = (
    "import api.config as c; "
    "print(c.STATE_DIR)"
)


def _state_dir_for_env(**env_overrides) -> Path:
    """Import api.config in a fresh subprocess under the given env and return
    the resolved STATE_DIR it computes. None-valued overrides unset the var."""
    env = dict(os.environ)
    # Start from a clean slate for the two vars under test so the parent
    # process's pytest values don't bleed in.
    env.pop("ARES_HOME", None)
    env.pop("ARES_WEBUI_STATE_DIR", None)
    for key, value in env_overrides.items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = str(value)
    out = subprocess.run(
        [sys.executable, "-c", _PROBE],
        cwd=str(REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert out.returncode == 0, f"probe failed: {out.stderr}"
    return Path(out.stdout.strip()).resolve()


def _platform_default_state_dir() -> Path:
    """What STATE_DIR resolves to with ARES_HOME + STATE_DIR both unset."""
    return _state_dir_for_env()


def test_config_state_dir_defaults_to_ares_home_webui(tmp_path):
    ares_home = tmp_path / ".ares" / "profiles" / "isolated"
    ares_home.mkdir(parents=True)

    state_dir = _state_dir_for_env(ARES_HOME=ares_home)
    assert state_dir == (ares_home / "webui").resolve()


def test_config_state_dir_unchanged_for_normal_install_ares_home_unset():
    """Backward-compat: with ARES_HOME unset, STATE_DIR stays at the platform
    default `<~/.ares>/webui` — a normal install's state must NOT relocate
    (the #4449/#4454 state-dir move only affects an explicitly-set ARES_HOME).

    Cross-check: the unset-ARES_HOME result must NOT equal the result of
    pointing ARES_HOME at an arbitrary other base — i.e. the default is
    genuinely the platform home, not whatever the test environment injected."""
    default = _platform_default_state_dir()
    assert default.name == "webui"
    # Pointing ARES_HOME elsewhere produces a DIFFERENT dir, proving the unset
    # case resolves to the platform default rather than echoing an injected base.
    elsewhere = _state_dir_for_env(ARES_HOME="/tmp/ares-4449-elsewhere-base")
    assert elsewhere == Path("/tmp/ares-4449-elsewhere-base/webui").resolve()
    assert default != elsewhere


def test_config_state_dir_explicit_override_takes_precedence(tmp_path):
    """ARES_WEBUI_STATE_DIR always wins over the ARES_HOME-derived default,
    so an operator who pinned a state dir keeps it even in isolated mode."""
    ares_home = tmp_path / ".ares" / "profiles" / "isolated"
    ares_home.mkdir(parents=True)
    explicit = tmp_path / "custom-state"

    state_dir = _state_dir_for_env(
        ARES_HOME=ares_home,
        ARES_WEBUI_STATE_DIR=explicit,
    )
    assert state_dir == explicit.resolve()
