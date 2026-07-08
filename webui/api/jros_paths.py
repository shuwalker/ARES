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


def jros_source_root() -> Path:
    """Return the optional JROS source checkout root.

    Source-checkout access is only needed for source-tree features such as raw
    character library browsing. Runtime chat uses ``jaeger bridge`` instead.
    """
    override = os.environ.get(ARES_JROS_DIR_ENV, "").strip()
    if not override:
        raise RuntimeError(
            "ARES_JROS_DIR is not set. Point it at your JROS source checkout "
            "only if you want source-tree features such as the character library. "
            "JROS chat uses the installed bridge resolved from ARES_JAEGER_HOME, "
            "JAEGER_HOME, or the standard installer path."
        )
    return expand_path(override)


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


def jros_instance_name() -> str | None:
    """Return the requested JROS instance name, if configured."""
    return os.environ.get(ARES_JROS_INSTANCE_ENV, "").strip() or None


def jros_config_path() -> Path:
    """Resolve the most likely JROS instance config path without writing it."""
    explicit = os.getenv(ARES_JROS_CONFIG_PATH_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    instance_dir = os.getenv(JAEGER_INSTANCE_DIR_ENV, "").strip()
    if instance_dir:
        return expand_path(instance_dir) / "config.yaml"

    active_instance = Path("~/.jaeger/active_instance").expanduser()
    if active_instance.exists():
        instance_name = active_instance.read_text(encoding="utf-8").strip()
        if instance_name:
            return expand_path(Path("~/.jaeger/instances").expanduser() / instance_name / "config.yaml")

    installed_config = jros_install_tree() / "instance" / "default" / "config.yaml"
    if installed_config.exists():
        return expand_path(installed_config)

    return expand_path(Path("~/.jaeger/instances/default/config.yaml"))


def jros_update_repo() -> Path | None:
    """Return a git checkout to use for JROS update checks, if discoverable."""
    override = os.environ.get(ARES_JROS_DIR_ENV, "").strip()
    if override:
        return expand_path(override)

    home = jaeger_home()
    return home if home.is_dir() else None
