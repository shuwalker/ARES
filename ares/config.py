"""Config loading and watching for ARES.

Config lives at ~/.ares/config/ares.toml — plain TOML, human-editable.
Env-var overrides (ANTHROPIC_API_KEY, N8N_API_KEY, ARES_HOME) are pulled in
automatically via pydantic-settings BaseSettings.
"""

from __future__ import annotations

import os
import tomllib
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

def ares_home() -> Path:
    """Return ~/.ares, creating it if needed."""
    base = Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))
    base.mkdir(parents=True, exist_ok=True)
    return base


def ares_paths() -> dict[str, Path]:
    home = ares_home()
    paths = {
        "home": home,
        "config": home / "config",
        "memory": home / "memory",
        "memory_episodic": home / "memory" / "episodic",
        "memory_preferences": home / "memory" / "preferences",
        "memory_tools": home / "memory" / "tools",
        "memory_knowledge": home / "memory" / "knowledge",
        "memory_projects": home / "memory" / "projects",
        "tasks": home / "tasks",
        "n8n_workflows": home / "n8n-workflows",
        "logs": home / "logs",
        "cache": home / "cache",
        "socket": home / "ares.sock",
    }
    for key, path in paths.items():
        if key != "socket":
            path.mkdir(parents=True, exist_ok=True)
    return paths


# ---------------------------------------------------------------------------
# Config models
# ---------------------------------------------------------------------------

class LLMConfig(BaseModel):
    model_config = ConfigDict(validate_assignment=False)
    local_url: str = Field(default="http://localhost:1234/v1", description="Local OpenAI-compatible LLM endpoint URL")
    local_model: str = Field(default="local-model", description="Local model identifier")
    cloud_model: str = Field(default="claude-sonnet-4-6", description="Cloud model identifier (Anthropic)")
    cloud_api_key: str = Field(default="", description="Anthropic API key — falls back to ANTHROPIC_API_KEY env var")


class N8NConfig(BaseModel):
    model_config = ConfigDict(validate_assignment=False)
    url: str = Field(default="http://localhost:5678", description="n8n base URL")
    api_key: str = Field(default="", description="n8n API key — falls back to N8N_API_KEY env var")


class SyncConfig(BaseModel):
    model_config = ConfigDict(validate_assignment=False)
    enabled: bool = Field(default=True, description="Whether iCloud sync is enabled")
    icloud_path: str = Field(default="", description="Override iCloud path (auto-detected if empty)")


class DecisionConfig(BaseModel):
    model_config = ConfigDict(validate_assignment=False)
    cli_install_silence_minutes: int = Field(
        default=5,
        description="Minutes of silence after proposing a Homebrew install before auto-proceeding",
    )


class AresConfig(BaseSettings):
    """Root config. TOML provides sections; env-vars provide secrets."""

    model_config = SettingsConfigDict(
        env_prefix="",
        extra="ignore",
        case_sensitive=False,
        populate_by_name=True,
    )

    llm: LLMConfig = Field(default_factory=LLMConfig, description="LLM backend configuration")
    n8n: N8NConfig = Field(default_factory=N8NConfig, description="n8n workflow integration")
    sync: SyncConfig = Field(default_factory=SyncConfig, description="iCloud sync settings")
    decision: DecisionConfig = Field(default_factory=DecisionConfig, description="Autonomous decision policy")
    anthropic_api_key: str = Field(default="", alias="ANTHROPIC_API_KEY", description="Env-var override for cloud LLM key")
    n8n_api_key: str = Field(default="", alias="N8N_API_KEY", description="Env-var override for n8n API key")
    extra_toml: dict[str, Any] = Field(
        default_factory=dict,
        description="Raw extra TOML sections preserved for forward-compatibility",
    )


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

_CONFIG_PATH: Path | None = None
_CONFIG: AresConfig | None = None


def config_path() -> Path:
    global _CONFIG_PATH
    if _CONFIG_PATH is None:
        paths = ares_paths()
        _CONFIG_PATH = paths["config"] / "ares.toml"
    return _CONFIG_PATH


def load_config() -> AresConfig:
    global _CONFIG
    path = config_path()
    raw: dict[str, Any] = {}
    if path.exists():
        with open(path, "rb") as fh:
            raw = tomllib.load(fh)

    cfg = AresConfig.model_validate(
        {
            "llm": raw.get("llm", {}),
            "n8n": raw.get("n8n", {}),
            "sync": raw.get("sync", {}),
            "decision": raw.get("decision", {}),
            "extra_toml": {
                k: v for k, v in raw.items()
                if k not in ("llm", "n8n", "sync", "decision")
            },
        }
    )

    # Preserve old precedence: TOML value wins if non-empty, else env-var fallback.
    if not cfg.llm.cloud_api_key and cfg.anthropic_api_key:
        cfg.llm.cloud_api_key = cfg.anthropic_api_key
    if not cfg.n8n.api_key and cfg.n8n_api_key:
        cfg.n8n.api_key = cfg.n8n_api_key

    _CONFIG = cfg
    return cfg


def get_config() -> AresConfig:
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = load_config()
    return _CONFIG


def write_default_config() -> Path:
    """Write a default config file if none exists."""
    import tomli_w

    path = config_path()
    if path.exists():
        return path

    data = {
        "llm": {
            "local_url": "http://localhost:1234/v1",
            "local_model": "local-model",
            "cloud_model": "claude-sonnet-4-6",
            "cloud_api_key": "",  # Set ANTHROPIC_API_KEY env var
        },
        "n8n": {
            "url": "http://localhost:5678",
            "api_key": "",
        },
        "sync": {
            "enabled": True,
            "icloud_path": "",
        },
        "decision": {
            "cli_install_silence_minutes": 5,
        },
    }

    with open(path, "wb") as fh:
        tomli_w.dump(data, fh)

    return path
