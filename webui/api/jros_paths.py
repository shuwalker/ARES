"""Shared JROS/JAEGER path resolution for ARES WebUI.

ARES treats JROS as a peer runtime. This module centralizes every filesystem
path ARES needs for that integration so WebUI code does not grow competing
ideas of where Jaeger/JROS lives.

Conventions:
- ARES_JAEGER_HOME: ARES-specific installed Jaeger/JROS home override.
- JAEGER_HOME: JROS-wide installed Jaeger/JROS home override.
- ARES_JROS_DIR: optional source checkout for source-tree features only.
- ARES_JROS_CONFIG_PATH: explicit instance config.yaml override.
- JAEGER_INSTANCE_DIR: explicit instance directory override.
"""
from __future__ import annotations

import os
from pathlib import Path

ARES_JAEGER_HOME_ENV = "ARES_JAEGER_HOME"
JAEGER_HOME_ENV = "JAEGER_HOME"
ARES_JROS_DIR_ENV = "ARES_JROS_DIR"
ARES_JROS_CONFIG_PATH_ENV = "ARES_JROS_CONFIG_PATH"
JAEGER_INSTANCE_DIR_ENV = "JAEGER_INSTANCE_DIR"
ARES_CHARACTER_DIR_ENV = "ARES_CHARACTER_DIR"
ARES_PERSONA_DIR_ENV = "ARES_PERSONA_DIR"
ARES_JROS_INSTANCE_ENV = "ARES_JROS_INSTANCE"


def expand_path(value: str | os.PathLike[str]) -> Path:
    """Expand user/env syntax and return an absolute path."""
    return Path(os.path.expandvars(str(value))).expanduser().resolve()


def jaeger_home() -> Path:
    """Return the installed Jaeger/JROS home.

    This is the runtime install that contains the ``jaeger`` launcher and the
    installed ``jaeger_os`` tree. It is not necessarily a developer source
    checkout.
    """
    raw = os.environ.get(ARES_JAEGER_HOME_ENV) or os.environ.get(JAEGER_HOME_ENV) or "~/jaeger"
    return expand_path(raw)


def jaeger_launcher() -> Path:
    """Return the expected installed ``jaeger`` bridge launcher path."""
    return jaeger_home() / "jaeger"


def discover_jros_source_root() -> Path | None:
    """Best-effort discovery for a local JROS source checkout.

    ``ARES_JROS_DIR`` remains the explicit override. The fallback candidates
    cover the common developer layouts used by ARES itself: sibling checkouts
    under the same GitHub folder, ``~/GitHub/JROS``, and ``~/JROS``.
    """
    override = os.environ.get(ARES_JROS_DIR_ENV, "").strip()
    candidates: list[Path] = []
    if override:
        candidates.append(expand_path(override))

    ares_root = Path(__file__).resolve().parents[2]
    candidates.extend([
        ares_root.parent / "JROS",
        Path("~/GitHub/JROS").expanduser(),
        Path("~/JROS").expanduser(),
    ])

    seen: set[Path] = set()
    for candidate in candidates:
        try:
            root = candidate.expanduser().resolve()
        except OSError:
            continue
        if root in seen:
            continue
        seen.add(root)
        if (root / "jaeger_os").is_dir():
            return root
    return None


def jros_source_root() -> Path:
    """Return the optional JROS source checkout root.

    Source-checkout access is only needed for source-tree features such as raw
    character library browsing. Runtime chat uses ``jaeger bridge`` instead.
    """
    root = discover_jros_source_root()
    if root is None:
        raise RuntimeError(
            "ARES_JROS_DIR is not set. Point it at your JROS source checkout "
            "only if you want source-tree features such as the character library. "
            "JROS chat uses the installed bridge resolved from ARES_JAEGER_HOME, "
            "JAEGER_HOME, or the standard installer path."
        )
    return root


def jros_install_tree() -> Path:
    """Return the installed ``jaeger_os`` tree under the Jaeger/JROS home."""
    return jaeger_home() / "jaeger_os"


def character_dir() -> Path:
    """Return the character/v1 directory.

    ``ARES_CHARACTER_DIR`` wins. Otherwise use the installed JROS tree first,
    falling back to a source checkout only when the install tree is absent.
    """
    explicit = os.environ.get(ARES_CHARACTER_DIR_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    installed = jros_install_tree() / "personality" / "characters"
    if installed.exists():
        return installed

    return jros_source_root() / "jaeger_os" / "personality" / "characters"


def legacy_persona_dir() -> Path:
    """Return the legacy persona/v1 directory."""
    explicit = os.environ.get(ARES_PERSONA_DIR_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    installed = jros_install_tree() / "agent" / "personas"
    if installed.exists():
        return installed

    return jros_source_root() / "jaeger_os" / "agent" / "personas"


def _read_first_existing_text(paths: list[Path]) -> str | None:
    """Return stripped text from the first readable file in ``paths``."""
    for path in paths:
        try:
            if path.exists():
                value = path.read_text(encoding="utf-8").strip()
                if value:
                    return value
        except OSError:
            continue
    return None


def _active_instance_files() -> list[Path]:
    """Known JROS active-instance marker locations, newest runtime first."""
    home = jaeger_home()
    return [
        home / ".jaeger_os" / "active_instance",
        home / ".jaeger" / "active_instance",
        Path("~/.jaeger/active_instance").expanduser(),
    ]


def jros_instance_name() -> str | None:
    """Return the requested JROS instance name, if configured.

    Resolution order:
      1. ARES_JROS_INSTANCE env var (ARES-specific override)
      2. JAEGER_INSTANCE_NAME env var (JROS-native override)
      3. ``<JAEGER_HOME>/.jaeger_os/active_instance`` (JROS 0.7 runtime)
      4. legacy active-instance marker files
      5. None (last-resort JROS bridge default)

    ARES passes this value as ``jaeger bridge <instance>`` because JROS 0.7 can
    emit a ready frame from the implicit default while the first real turn still
    stalls. The explicit instance argument is the verified working contract.
    """
    explicit = os.environ.get(ARES_JROS_INSTANCE_ENV, "").strip()
    if explicit:
        return explicit
    native = os.environ.get("JAEGER_INSTANCE_NAME", "").strip()
    if native:
        return native
    return _read_first_existing_text(_active_instance_files())


def jros_config_path() -> Path:
    """Resolve the most likely JROS instance config path without writing it."""
    explicit = os.getenv(ARES_JROS_CONFIG_PATH_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    instance_dir = os.getenv(JAEGER_INSTANCE_DIR_ENV, "").strip()
    if instance_dir:
        return expand_path(instance_dir) / "config.yaml"

    instance_name = jros_instance_name()
    if instance_name:
        runtime_config = jaeger_home() / ".jaeger_os" / "instances" / instance_name / "config.yaml"
        if runtime_config.exists():
            return expand_path(runtime_config)
        legacy_config = Path("~/.jaeger/instances").expanduser() / instance_name / "config.yaml"
        if legacy_config.exists():
            return expand_path(legacy_config)

    installed_config = jaeger_home() / ".jaeger_os" / "instances" / "default" / "config.yaml"
    if installed_config.exists():
        return expand_path(installed_config)

    return expand_path(Path("~/.jaeger/instances/default/config.yaml"))


def jros_update_repo() -> Path | None:
    """Return a git checkout to use for JROS update checks, if discoverable."""
    source = discover_jros_source_root()
    if source is not None:
        return source

    home = jaeger_home()
    return home if home.is_dir() else None
