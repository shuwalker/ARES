"""Auto-discover installed AI frameworks on macOS/Linux and map them to ARES adapters."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class DiscoveredAdapter:
    adapter_id: str
    display_name: str
    detected: bool
    binary_path: str | None = None
    config_dir: str | None = None
    version: str | None = None
    default_model: str | None = None
    default_provider: str | None = None
    details: dict[str, Any] = field(default_factory=dict)
    mcp_servers: list[dict[str, Any]] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "adapter_id": self.adapter_id,
            "display_name": self.display_name,
            "detected": self.detected,
            "binary_path": self.binary_path,
            "config_dir": self.config_dir,
            "version": self.version,
            "default_model": self.default_model,
            "default_provider": self.default_provider,
            "details": self.details,
            "mcp_servers": self.mcp_servers,
        }


# Map ARES adapter IDs to likely binary names and config directories
_ADAPTER_SPECS: list[dict[str, Any]] = [
    {
        "adapter_id": "hermes_local",
        "display_name": "Hermes Agent",
        "binaries": ["hermes"],
        "config_dirs": ["~/.hermes"],
        "model_file": "config.yaml",
    },
    {
        "adapter_id": "claude_local",
        "display_name": "Claude Code",
        "binaries": ["claude"],
        "config_dirs": ["~/.claude"],
    },
    {
        "adapter_id": "codex_local",
        "display_name": "OpenAI Codex",
        "binaries": ["codex"],
        "config_dirs": ["~/.codex"],
    },
    {
        "adapter_id": "gemini_local",
        "display_name": "Google Gemini",
        "binaries": ["gemini"],
        "config_dirs": ["~/.gemini"],
    },
    {
        "adapter_id": "grok_local",
        "display_name": "xAI Grok",
        "binaries": ["grok"],
        "config_dirs": ["~/.grok"],
    },
    {
        "adapter_id": "opencode_local",
        "display_name": "OpenCode",
        "binaries": ["opencode"],
        "config_dirs": ["~/.opencode"],
    },
    {
        "adapter_id": "cursor_local",
        "display_name": "Cursor",
        "binaries": ["cursor"],
        "config_dirs": ["~/.cursor", "~/Library/Application Support/Cursor"],
    },
    {
        "adapter_id": "pi_local",
        "display_name": "Pi Coding Agent",
        "binaries": ["pi"],
        "config_dirs": ["~/.pi"],
        "model_file": "agent/settings.json",
    },
    {
        "adapter_id": "ollama_local",
        "display_name": "Ollama",
        "binaries": ["ollama"],
        "config_dirs": ["~/.ollama"],
    },
    {
        "adapter_id": "jros_local",
        "display_name": "JaegerAI",
        "binaries": ["jaeger", "jros"],
        "config_dirs": [],
    },
]


def _expand(path: str) -> Path:
    return Path(path).expanduser()


def _run(args: list[str], timeout: int = 10) -> str | None:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "NO_COLOR": "1"},
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def _probe_version(binary: str) -> str | None:
    for flag in ["--version", "-v", "version"]:
        out = _run([binary, flag], timeout=5)
        if out:
            first = out.splitlines()[0]
            return first[:120]
    return None


def _read_json(path: Path, max_size: int = 50_000) -> dict[str, Any] | None:
    try:
        if path.exists() and path.stat().st_size <= max_size:
            with open(path) as f:
                return json.load(f)
    except Exception:
        pass
    return None


def _read_yaml_front(path: Path, max_size: int = 50_000) -> dict[str, Any] | None:
    try:
        if not path.exists() or path.stat().st_size > max_size:
            return None
        import yaml
        with open(path) as f:
            data = yaml.safe_load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return None


def _find_mcp_servers(config_dir: Path) -> list[dict[str, Any]]:
    servers: list[dict[str, Any]] = []
    candidates = [
        config_dir / ".mcp.json",
        config_dir / "mcp_config.json",
        config_dir / "config" / "mcp_config.json",
    ]
    for cand in candidates:
        data = _read_json(cand)
        if data and "mcpServers" in data:
            for name, cfg in data["mcpServers"].items():
                servers.append({
                    "name": name,
                    "command": cfg.get("command"),
                    "args": cfg.get("args"),
                    "source_file": str(cand),
                })
    return servers


def _fetch_ollama_default_model() -> str | None:
    try:
        import requests
        r = requests.get("http://127.0.0.1:11434/api/tags", timeout=3)
        if r.status_code == 200:
            models = [m.get("name") for m in r.json().get("models", [])]
            preferred = [m for m in models if "qwen" in m.lower() or "kai" in m.lower() or "llama" in m.lower()]
            return preferred[0] if preferred else (models[0] if models else None)
    except Exception:
        pass
    return None


def _extract_model_info(adapter_id: str, config_dir: Path) -> dict[str, Any]:
    info: dict[str, Any] = {}
    if adapter_id == "pi_local":
        settings = _read_json(config_dir / "agent" / "settings.json")
        if settings:
            configured = settings.get("defaultModel")
            # If the configured model isn't actually available locally, override with a real Ollama tag
            available = _fetch_ollama_default_model()
            if configured:
                info["configured_model"] = configured
            info["default_model"] = available or configured
            info["default_provider"] = settings.get("defaultProvider")
    elif adapter_id == "codex_local":
        cfg = _read_yaml_front(config_dir / "config.toml")
        if cfg:
            info["default_model"] = cfg.get("model")
    elif adapter_id == "grok_local":
        cfg = _read_yaml_front(config_dir / "config.toml")
        if cfg:
            cli = cfg.get("cli", {})
            info["default_model"] = cli.get("fork_secondary_model")
    elif adapter_id == "hermes_local":
        cfg = _read_yaml_front(config_dir / "config.yaml")
        if cfg:
            model = cfg.get("model", {})
            info["default_model"] = model.get("default")
            info["default_provider"] = model.get("provider")
    elif adapter_id == "ollama_local":
        info["default_model"] = _fetch_ollama_default_model()
    return info


def discover_frameworks() -> list[DiscoveredAdapter]:
    discovered: list[DiscoveredAdapter] = []
    for spec in _ADAPTER_SPECS:
        binary_path = None
        for name in spec["binaries"]:
            binary_path = shutil.which(name)
            if binary_path:
                break

        config_dir = None
        for d in spec["config_dirs"]:
            p = _expand(d)
            if p.exists():
                config_dir = str(p)
                break

        detected = bool(binary_path or config_dir)
        version = _probe_version(binary_path) if binary_path else None

        info: dict[str, Any] = {}
        mcp_servers: list[dict[str, Any]] = []
        if config_dir:
            cfg_path = Path(config_dir)
            info = _extract_model_info(spec["adapter_id"], cfg_path)
            mcp_servers = _find_mcp_servers(cfg_path)

        discovered.append(DiscoveredAdapter(
            adapter_id=spec["adapter_id"],
            display_name=spec["display_name"],
            detected=detected,
            binary_path=binary_path,
            config_dir=config_dir,
            version=version,
            default_model=info.get("default_model"),
            default_provider=info.get("default_provider"),
            details={},
            mcp_servers=mcp_servers,
        ))

    return discovered


def discover_summary() -> dict[str, Any]:
    adapters = discover_frameworks()
    return {
        "scanned_at": None,  # caller can fill in ISO timestamp
        "adapters": [a.as_dict() for a in adapters],
        "detected_count": sum(1 for a in adapters if a.detected),
        "available_ids": [a.adapter_id for a in adapters if a.detected],
    }
