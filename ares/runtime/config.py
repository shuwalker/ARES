"""ARES configuration — TOML config loading, validation, and defaults.

Config resolution order:
1. ~/.ares/config/ares.toml (user overrides)
2. ~/.ares/.env (secrets, API keys)
3. Environment variables (ARES_ prefix)
4. Built-in defaults below
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

logger = logging.getLogger("ares.runtime.config")


def _get_ares_home() -> Path:
    """Resolve ARES_HOME from env or default."""
    return Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))


def ares_home() -> Path:
    """Return ~/.ares, creating it if needed."""
    base = _get_ares_home()
    base.mkdir(parents=True, exist_ok=True)
    return base


def ares_paths() -> dict[str, Path]:
    """Return a dict of standard ARES directory paths."""
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
        "approvals": home / "approvals",
        "n8n_workflows": home / "n8n-workflows",
        "logs": home / "logs",
        "cache": home / "cache",
        "socket": home / "ares.sock",
    }
    for key, path in paths.items():
        if key != "socket":
            path.mkdir(parents=True, exist_ok=True)
    return paths


_CONFIG_PATH: Optional[Path] = None
_CONFIG: Optional["AresConfig"] = None


def config_path() -> Path:
    """Return the path to ares.toml."""
    global _CONFIG_PATH
    if _CONFIG_PATH is None:
        paths = ares_paths()
        _CONFIG_PATH = paths["config"] / "ares.toml"
    return _CONFIG_PATH


def get_config() -> "AresConfig":
    """Return the cached AresConfig, loading it on first call."""
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = load_config()
    return _CONFIG


def _env_bool(key: str, default: bool = False) -> bool:
    """Read a boolean from environment variable."""
    val = os.environ.get(key, "").lower()
    if val in ("1", "true", "yes", "on"):
        return True
    if val in ("0", "false", "no", "off"):
        return False
    return default


def _env_str(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


@dataclass
class AgentConfig:
    """Which brain backend ARES uses and its connection settings."""

    backend: str = "hermes"  # "hermes" | "lilith" | "local"

    # Hermes settings
    hermes_api_url: str = "http://localhost:8321"
    hermes_api_key: str = ""

    # Lilith settings
    lilith_zmq_host: str = "127.0.0.1"
    lilith_input_port: int = 5571
    lilith_output_port: int = 5572

    # Local / Ollama settings
    local_model: str = "gemma3:12b"
    local_ollama_url: str = "http://localhost:11434"
    ollama_num_ctx: int = 65536  # Context window for Ollama requests

    # Cloud LLM settings (Anthropic)
    cloud_model: str = "claude-sonnet-4-6"
    cloud_api_key: str = ""  # Falls back to ANTHROPIC_API_KEY env var if empty

    def agent_dict(self) -> dict:
        """Return config as a dict suitable for load_backend()."""
        return {
            "api_url": self.hermes_api_url,
            "api_key": self.hermes_api_key,
            "zmq_host": self.lilith_zmq_host,
            "input_port": self.lilith_input_port,
            "output_port": self.lilith_output_port,
            "model": self.local_model,
            "ollama_url": self.local_ollama_url,
        }


@dataclass
class FaceConfig:
    """Face rendering settings."""

    default_style: str = "blackfire"
    intensity: float = 0.60


@dataclass
class SyncConfig:
    """iCloud Drive sync settings."""

    enabled: bool = True
    icloud_path: str = ""  # Auto-detect if empty


@dataclass
class TelemetryConfig:
    """OSC telemetry to an avatar / render node."""

    osc_enabled: bool = False
    osc_host: str = "127.0.0.1"
    osc_port: int = 9000


@dataclass
class IPCConfig:
    """ZeroMQ IPC between the Python daemon and the desktop app."""

    socket_path: str = "/tmp/ares_ipc.sock"


@dataclass
class AresConfig:
    """Top-level ARES configuration."""

    home: Path = field(default_factory=_get_ares_home)
    agent: AgentConfig = field(default_factory=AgentConfig)
    face: FaceConfig = field(default_factory=FaceConfig)
    sync: SyncConfig = field(default_factory=SyncConfig)
    telemetry: TelemetryConfig = field(default_factory=TelemetryConfig)
    ipc: IPCConfig = field(default_factory=IPCConfig)

    # Gateway
    gateway_host: str = "127.0.0.1"
    gateway_port: int = 7860

    # MCP servers
    mcp_perception_url: str = "http://localhost:9512"
    mcp_voice_url: str = "http://localhost:9513"
    mcp_avatar_url: str = "http://localhost:9514"
    mcp_mac_url: str = "http://localhost:9501"


def load_config(path: Optional[Path] = None) -> AresConfig:
    """Load ARES config from TOML file, falling back to defaults.

    If TOML parsing is unavailable or the file doesn't exist, returns
    a config with all defaults applied.
    """
    home = _get_ares_home()
    config_path = path or (home / "config" / "ares.toml")

    config = AresConfig(home=home)

    # Override from environment variables
    config.gateway_host = _env_str("ARES_GATEWAY_HOST", config.gateway_host)
    config.gateway_port = int(_env_str("ARES_GATEWAY_PORT", str(config.gateway_port)))
    config.agent.backend = _env_str("ARES_AGENT_BACKEND", config.agent.backend)
    config.agent.hermes_api_url = _env_str("ARES_HERMES_URL", config.agent.hermes_api_url)
    config.agent.hermes_api_key = _env_str("ARES_HERMES_API_KEY", config.agent.hermes_api_key)
    config.agent.local_model = _env_str("ARES_LOCAL_MODEL", config.agent.local_model)
    config.agent.local_ollama_url = _env_str("ARES_OLLAMA_URL", config.agent.local_ollama_url)
    _ollama_num_ctx = _env_str("OLLAMA_NUM_CTX", "")
    if _ollama_num_ctx:
        config.agent.ollama_num_ctx = int(_ollama_num_ctx)

    # Load .env secrets if present
    env_file = home / ".env"
    if env_file.exists():
        _load_env_file(env_file)

    # Load TOML config if available
    if config_path.exists():
        try:
            _apply_toml(config, config_path)
        except Exception as e:
            logger.warning("Failed to load config from %s: %s", config_path, e)

    return config


def _load_env_file(path: Path) -> None:
    """Load key=value pairs from .env file into os.environ (if not already set)."""
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("\"'")
        if key and key not in os.environ:
            os.environ[key] = value


def _apply_toml(config: AresConfig, path: Path) -> None:
    """Apply TOML config file values to an AresConfig."""
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib  # type: ignore[no-redef]
        except ImportError:
            logger.warning("No TOML parser available — skipping %s", path)
            return

    with open(path, "rb") as f:
        data = tomllib.load(f)

    # Agent section
    agent = data.get("agent", {})
    if "backend" in agent:
        config.agent.backend = agent["backend"]
    hermes = agent.get("hermes", {})
    if "api_url" in hermes:
        config.agent.hermes_api_url = hermes["api_url"]
    if "api_key" in hermes:
        config.agent.hermes_api_key = hermes["api_key"]
    lilith = agent.get("lilith", {})
    if "zmq_host" in lilith:
        config.agent.lilith_zmq_host = lilith["zmq_host"]
    if "input_port" in lilith:
        config.agent.lilith_input_port = lilith["input_port"]
    if "output_port" in lilith:
        config.agent.lilith_output_port = lilith["output_port"]
    local = agent.get("local", {})
    if "model" in local:
        config.agent.local_model = local["model"]
    if "ollama_url" in local:
        config.agent.local_ollama_url = local["ollama_url"]
    if "num_ctx" in local:
        config.agent.ollama_num_ctx = int(local["num_ctx"])
    cloud = agent.get("cloud", {})
    if "model" in cloud:
        config.agent.cloud_model = cloud["model"]
    if "api_key" in cloud:
        config.agent.cloud_api_key = cloud["api_key"]

    # Face section
    face = data.get("face", {})
    if "default_style" in face:
        config.face.default_style = face["default_style"]
    if "intensity" in face:
        config.face.intensity = float(face["intensity"])

    # Gateway section
    gateway = data.get("gateway", {})
    if "host" in gateway:
        config.gateway_host = gateway["host"]
    if "port" in gateway:
        config.gateway_port = int(gateway["port"])

    # Telemetry section
    telemetry = data.get("telemetry", {})
    osc = telemetry.get("osc", {})
    if "enabled" in osc:
        config.telemetry.osc_enabled = bool(osc["enabled"])
    if "host" in osc:
        config.telemetry.osc_host = osc["host"]
    if "port" in osc:
        config.telemetry.osc_port = int(osc["port"])

    # IPC section
    ipc = data.get("ipc", {})
    if "socket_path" in ipc:
        config.ipc.socket_path = ipc["socket_path"]


def write_default_config() -> Path:
    """Write a default config file if none exists."""
    try:
        import tomli_w
    except ImportError:
        logger.warning("tomli_w not installed — skipping default config write")
        return config_path()

    path = config_path()
    if path.exists():
        return path

    data = {
        "agent": {
            "backend": "hermes",
            "hermes": {"api_url": "http://localhost:8321", "api_key": ""},
            "lilith": {"zmq_host": "127.0.0.1", "input_port": 5571, "output_port": 5572},
            "local": {"model": "gemma3:12b", "ollama_url": "http://localhost:11434", "num_ctx": 65536},
        },
        "face": {"default_style": "blackfire", "intensity": 0.60},
        "gateway": {"host": "127.0.0.1", "port": 7860},
    }

    with open(path, "wb") as fh:
        tomli_w.dump(data, fh)

    return path
