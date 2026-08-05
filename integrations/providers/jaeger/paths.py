"""Shared JaegerAI dependency resolution for ARES.

ARES talks to JaegerAI through its public launcher/bridge contract. This module
centralizes dependency discovery so production installs and sibling development
checkouts use the same validated boundary.

Conventions:
- ARES_JAEGER_HOME: ARES-specific JaegerAI product-root override.
- JAEGER_HOME: JaegerAI's product-root override.
- ARES_JAEGER_SOURCE_DIR: optional development checkout override.
- Legacy JROS variables are accepted only as migration inputs.
- JAEGER_INSTANCE_DIR: explicit instance directory override.
"""
from __future__ import annotations

import os
from pathlib import Path

ARES_JAEGER_HOME_ENV = "ARES_JAEGER_HOME"
JAEGER_HOME_ENV = "JAEGER_HOME"
ARES_JAEGER_SOURCE_DIR_ENV = "ARES_JAEGER_SOURCE_DIR"
ARES_JAEGER_CONFIG_PATH_ENV = "ARES_JAEGER_CONFIG_PATH"
LEGACY_JROS_DIR_ENV = "ARES_JROS_DIR"
LEGACY_JROS_CONFIG_PATH_ENV = "ARES_JROS_CONFIG_PATH"
JAEGER_INSTANCE_DIR_ENV = "JAEGER_INSTANCE_DIR"
ARES_CHARACTER_DIR_ENV = "ARES_CHARACTER_DIR"
ARES_PERSONA_DIR_ENV = "ARES_PERSONA_DIR"
ARES_JAEGER_INSTANCE_ENV = "ARES_JAEGER_INSTANCE"
LEGACY_JROS_INSTANCE_ENV = "ARES_JROS_INSTANCE"


def expand_path(value: str | os.PathLike[str]) -> Path:
    """Expand user/env syntax and return an absolute path."""
    return Path(os.path.expandvars(str(value))).expanduser().resolve()


def is_jaeger_ai_root(path: str | os.PathLike[str]) -> bool:
    """Return whether ``path`` is a current JaegerAI product checkout/install.

    A launcher or a ``jaeger_os`` package alone is not sufficient: legacy JROS
    used both and must never be mistaken for JaegerAI. The product package is
    the stable capability marker shared by source and installed layouts.
    """
    try:
        root = expand_path(path)
        launcher = root / "jaeger"
        return (
            (root / "jaeger_ai").is_dir()
            and launcher.is_file()
            and os.access(launcher, os.X_OK)
        )
    except OSError:
        return False


def jaeger_home() -> Path:
    """Return the selected JaegerAI product root.

    Explicit configuration wins. Otherwise the standard ``~/jaeger`` install
    wins when it is current JaegerAI; a sibling development checkout is the
    fallback. Returning the conventional install path when neither exists lets
    status surfaces explain the missing dependency without inventing one.
    """
    raw = (os.environ.get(ARES_JAEGER_HOME_ENV) or os.environ.get(JAEGER_HOME_ENV) or "").strip()
    if raw:
        return expand_path(raw)
    installed = expand_path("~/jaeger")
    if is_jaeger_ai_root(installed):
        return installed
    source = discover_jaeger_ai_source_root()
    return source if source is not None else installed


def jaeger_launcher() -> Path:
    """Return the expected installed ``jaeger`` bridge launcher path."""
    return jaeger_home() / "jaeger"


def discover_jaeger_ai_source_root() -> Path | None:
    """Discover a current JaegerAI checkout without accepting legacy JROS."""
    override = (
        os.environ.get(ARES_JAEGER_SOURCE_DIR_ENV)
        or os.environ.get(LEGACY_JROS_DIR_ENV)
        or ""
    ).strip()
    if override:
        root = expand_path(override)
        return root if is_jaeger_ai_root(root) else None

    repository_root = Path(__file__).resolve().parents[3]
    candidates = [
        repository_root.parent / "JaegerAI",
        Path("~/GitHub/JaegerAI").expanduser(),
        Path("~/JaegerAI").expanduser(),
    ]

    seen: set[Path] = set()
    for candidate in candidates:
        try:
            root = candidate.expanduser().resolve()
        except OSError:
            continue
        if root in seen:
            continue
        seen.add(root)
        if is_jaeger_ai_root(root):
            return root
    return None


def discover_jros_source_root() -> Path | None:
    """Legacy callable name; results are restricted to current JaegerAI."""
    return discover_jaeger_ai_source_root()


def jros_source_root() -> Path:
    """Compatibility callable returning the selected JaegerAI source root.

    Source-checkout access is only needed for source-tree features such as raw
    character library browsing. Runtime chat uses ``jaeger bridge`` instead.
    """
    root = discover_jros_source_root()
    if root is None:
        raise RuntimeError(
            "No JaegerAI development checkout was found. Set ARES_JAEGER_SOURCE_DIR "
            "only when using a nonstandard checkout. Chat uses the bridge resolved "
            "from ARES_JAEGER_HOME, "
            "JAEGER_HOME, or the standard installer path."
        )
    return root


def jros_install_tree() -> Path:
    """Legacy callable returning the current JaegerAI package tree."""
    return jaeger_home() / "jaeger_ai"


def character_dir() -> Path:
    """Return JaegerAI's character library directory.

    ``ARES_CHARACTER_DIR`` wins. Otherwise use the selected JaegerAI tree first,
    falling back to a source checkout only when the install tree is absent.
    """
    explicit = os.environ.get(ARES_CHARACTER_DIR_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    installed = jros_install_tree() / "personality" / "characters"
    if installed.exists():
        return installed

    return jros_source_root() / "jaeger_ai" / "personality" / "characters"


def legacy_persona_dir() -> Path:
    """Return the legacy persona/v1 directory."""
    explicit = os.environ.get(ARES_PERSONA_DIR_ENV, "").strip()
    if explicit:
        return expand_path(explicit)

    installed = jros_install_tree() / "agent" / "personas"
    if installed.exists():
        return installed

    return jros_source_root() / "jaeger_ai" / "agent" / "personas"


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
    explicit = (
        os.environ.get(ARES_JAEGER_INSTANCE_ENV)
        or os.environ.get(LEGACY_JROS_INSTANCE_ENV)
        or ""
    ).strip()
    if explicit:
        return explicit
    native = os.environ.get("JAEGER_INSTANCE_NAME", "").strip()
    if native:
        return native
    return _read_first_existing_text(_active_instance_files())


def jros_config_path() -> Path:
    """Resolve the most likely JROS instance config path without writing it."""
    explicit = (
        os.getenv(ARES_JAEGER_CONFIG_PATH_ENV)
        or os.getenv(LEGACY_JROS_CONFIG_PATH_ENV)
        or ""
    ).strip()
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
