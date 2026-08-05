"""Discover configured LLM providers and installed local models.

Reference approach: hermes-paperclip-adapter ``detect-model.ts`` —
read Hermes config for default model/provider, then expand with
auth/credential pool, Ollama local tags, and Jaeger GGUF installs.

These catalogs feed adapter ``inventory()`` so Chat can list only what
is actually configured or installed for that backend.
"""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from api.backends.catalog import infer_model_location, model_entry

logger = logging.getLogger(__name__)

# Known Hermes CLI providers (paperclip VALID_PROVIDERS + common extras).
HERMES_KNOWN_PROVIDERS = (
    "auto",
    "openrouter",
    "nous",
    "openai-codex",
    "copilot",
    "copilot-acp",
    "anthropic",
    "huggingface",
    "zai",
    "kimi-coding",
    "minimax",
    "minimax-cn",
    "kilocode",
    "ollama",
    "ollama-cloud",
    "openai",
    "xai",
    "xai-oauth",
    "gemini",
    "google",
)


def _safe_yaml_load(path: Path) -> dict[str, Any]:
    try:
        import yaml  # type: ignore

        if not path.is_file():
            return {}
        with path.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        logger.debug("YAML load failed for %s", path, exc_info=True)
        return {}


def _safe_json_load(path: Path) -> dict[str, Any]:
    try:
        if not path.is_file():
            return {}
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        logger.debug("JSON load failed for %s", path, exc_info=True)
        return {}


def list_ollama_local_models(
    *,
    base_url: str = "http://127.0.0.1:11434",
    timeout: float = 1.5,
) -> list[dict[str, Any]]:
    """Installed local Ollama models via ``/api/tags``."""
    url = base_url.rstrip("/") + "/api/tags"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="replace") or "{}")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return []
    models: list[dict[str, Any]] = []
    for row in payload.get("models") or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or row.get("model") or "").strip()
        if not name:
            continue
        models.append(
            model_entry(
                id=name,
                label=name,
                location="local",
                provider="ollama",
                in_use=False,
                source=f"{url}",
                notes="Installed local Ollama model.",
            )
        )
    return models


def detect_hermes_model_config(hermes_home: str | None = None) -> dict[str, Any]:
    """Paperclip-style detectModel: default + provider + base_url from config.yaml."""
    home = Path(hermes_home or os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
    cfg = _safe_yaml_load(home / "config.yaml")
    block = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
    default = str(block.get("default") or block.get("model") or "").strip()
    provider = str(block.get("provider") or "").strip()
    base_url = str(block.get("base_url") or "").strip()
    api_mode = str(block.get("api_mode") or "").strip()
    context_length = block.get("context_length")
    fallbacks: list[dict[str, str]] = []
    raw_fb = cfg.get("fallback_model") or []
    if isinstance(raw_fb, dict):
        raw_fb = [raw_fb]
    for item in raw_fb if isinstance(raw_fb, list) else []:
        if not isinstance(item, dict):
            continue
        mid = str(item.get("model") or item.get("default") or "").strip()
        prov = str(item.get("provider") or "").strip()
        if mid:
            fallbacks.append({"model": mid, "provider": prov})
    return {
        "model": default,
        "provider": provider,
        "base_url": base_url,
        "api_mode": api_mode,
        "context_length": context_length,
        "fallbacks": fallbacks,
        "source": str(home / "config.yaml"),
    }


def detect_hermes_configured_providers(hermes_home: str | None = None) -> list[dict[str, Any]]:
    """Providers with credentials / active config in Hermes auth store."""
    home = Path(hermes_home or os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
    auth = _safe_json_load(home / "auth.json")
    cfg = detect_hermes_model_config(str(home))
    providers: dict[str, dict[str, Any]] = {}

    def _add(name: str, *, status: str, source: str, notes: str = "") -> None:
        key = str(name or "").strip()
        if not key:
            return
        prev = providers.get(key)
        if prev and prev.get("status") == "configured" and status != "configured":
            return
        providers[key] = {
            "id": key,
            "label": key,
            "status": status,  # configured | referenced | known
            "source": source,
            "notes": notes,
        }

    # Config primary + fallbacks
    if cfg.get("provider"):
        _add(cfg["provider"], status="configured", source=cfg["source"], notes="Primary model.provider")
    for fb in cfg.get("fallbacks") or []:
        if fb.get("provider"):
            _add(fb["provider"], status="configured", source=cfg["source"], notes="fallback_model")

    # auth.json providers + credential_pool
    for name in (auth.get("providers") or {}):
        _add(str(name), status="configured", source=str(home / "auth.json"), notes="auth.providers")
    pool = auth.get("credential_pool") or {}
    if isinstance(pool, dict):
        for name, entries in pool.items():
            count = len(entries) if isinstance(entries, list) else 1
            _add(
                str(name),
                status="configured",
                source=str(home / "auth.json#credential_pool"),
                notes=f"{count} credential(s)",
            )
    active = str(auth.get("active_provider") or "").strip()
    if active:
        _add(active, status="configured", source=str(home / "auth.json"), notes="active_provider")

    # Local ollama always listed as available if daemon responds
    if list_ollama_local_models():
        _add("ollama", status="configured", source="http://127.0.0.1:11434/api/tags", notes="Local Ollama daemon")

    return sorted(providers.values(), key=lambda p: (p["status"] != "configured", p["id"]))


def discover_hermes_models(hermes_home: str | None = None) -> dict[str, Any]:
    """Models + providers for Hermes inventory / Chat model picker."""
    home = Path(hermes_home or os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
    cfg = detect_hermes_model_config(str(home))
    models: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()

    def _push(mid: str, provider: str | None, *, in_use: bool, source: str, notes: str = "") -> None:
        mid = str(mid or "").strip()
        if not mid or mid.startswith("(") or "{" in mid:
            return
        prov = str(provider or "").strip() or None
        key = (mid, prov or "")
        if key in seen:
            # Prefer in_use=True if we see it again
            if in_use:
                for m in models:
                    if m["id"] == mid and (m.get("provider") or "") == (prov or ""):
                        m["in_use"] = True
            return
        seen.add(key)
        models.append(
            model_entry(
                id=mid,
                label=mid,
                location=infer_model_location(prov, mid),
                provider=prov,
                in_use=in_use,
                source=source,
                notes=notes or None,
            )
        )

    if cfg.get("model"):
        _push(
            cfg["model"],
            cfg.get("provider"),
            in_use=True,
            source=cfg["source"],
            notes="Hermes config model.default",
        )
    for fb in cfg.get("fallbacks") or []:
        _push(
            fb.get("model") or "",
            fb.get("provider"),
            in_use=False,
            source=cfg["source"] + "#fallback_model",
            notes="Configured fallback",
        )

    # Local Ollama installs (always useful for Hermes when ollama is on PATH/daemon)
    for m in list_ollama_local_models():
        _push(
            m["id"],
            "ollama",
            in_use=False,
            source=str(m.get("source") or "ollama"),
            notes="Installed local Ollama model",
        )
        # If primary provider is ollama-cloud but same name exists locally, keep both locations
        # already handled by (id, provider) key.

    providers = detect_hermes_configured_providers(str(home))
    return {
        "models": models,
        "providers": providers,
        "default": {
            "model": cfg.get("model") or None,
            "provider": cfg.get("provider") or None,
            "base_url": cfg.get("base_url") or None,
        },
    }


def _jaeger_roots() -> list[Path]:
    roots: list[Path] = []
    for env_key in ("ARES_JAEGER_HOME", "JAEGER_HOME"):
        raw = os.environ.get(env_key)
        if raw:
            roots.append(Path(raw).expanduser())
    # Generic conventional locations only. A maintainer's own clone path must
    # never be a fallback: it leaks a username into a public repo and is dead
    # weight for every other user. Point ARES_JAEGER_HOME/JAEGER_HOME at a
    # non-standard checkout instead.
    roots.extend(
        [
            Path.home() / "jaeger",
            Path.home() / ".jaeger",
            Path.home() / "JaegerAI",
        ]
    )
    # de-dupe existing
    out: list[Path] = []
    seen: set[str] = set()
    for r in roots:
        key = str(r.resolve()) if r.exists() else str(r)
        if key in seen:
            continue
        seen.add(key)
        if r.exists():
            out.append(r)
    return out


def list_jaeger_installed_gguf(jaeger_home: Path | None = None) -> list[dict[str, Any]]:
    """Scan ``.jaeger_os/models/<id>/*.gguf`` installs."""
    homes = [jaeger_home] if jaeger_home else _jaeger_roots()
    models: list[dict[str, Any]] = []
    seen: set[str] = set()
    for home in homes:
        models_dir = home / ".jaeger_os" / "models"
        if not models_dir.is_dir():
            continue
        for child in sorted(models_dir.iterdir()):
            if not child.is_dir():
                continue
            ggufs = list(child.glob("*.gguf"))
            if not ggufs:
                continue
            mid = child.name
            if mid in seen:
                continue
            seen.add(mid)
            file_name = ggufs[0].name
            models.append(
                model_entry(
                    id=file_name if file_name else mid,
                    label=file_name or mid,
                    location="local",
                    provider="local",
                    in_use=False,
                    source=str(ggufs[0]),
                    notes=f"Installed GGUF under {child.name}",
                )
            )
    return models


def discover_jros_models(
    *,
    instance: str | None = None,
    gateway_health: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Configured + installed models/providers for JaegerAI/JROS."""
    health = gateway_health or {}
    inst = str(instance or health.get("instance") or "jarvis").strip() or "jarvis"
    models: list[dict[str, Any]] = []
    seen: set[str] = set()
    providers: list[dict[str, Any]] = []

    def _push(entry: dict[str, Any]) -> None:
        mid = str(entry.get("id") or "")
        if not mid or mid in seen or mid.startswith("("):
            return
        seen.add(mid)
        models.append(entry)

    # Live gateway model
    live_model = str(health.get("model") or "").strip()
    live_provider = str(health.get("provider") or "local").strip() or "local"
    if live_model:
        _push(
            model_entry(
                id=live_model,
                label=live_model,
                location=infer_model_location(live_provider, live_model),
                provider=live_provider,
                in_use=True,
                source="jros_gateway:/v1/health",
                notes="Currently loaded by gateway",
            )
        )

    # Instance config
    for home in _jaeger_roots():
        cfg_path = home / ".jaeger_os" / "instances" / inst / "config.yaml"
        cfg = _safe_yaml_load(cfg_path)
        if not cfg:
            continue
        mblock = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
        model_path = str(mblock.get("model_path") or "").strip()
        backend = str(mblock.get("backend") or "").strip() or "llama_cpp_python"
        if model_path:
            # Prefer matching gguf filename if present
            gguf_dir = home / ".jaeger_os" / "models" / model_path
            gguf_files = list(gguf_dir.glob("*.gguf")) if gguf_dir.is_dir() else []
            mid = gguf_files[0].name if gguf_files else model_path
            _push(
                model_entry(
                    id=mid,
                    label=mid,
                    location="local",
                    provider="local",
                    in_use=(mid == live_model or model_path in live_model.lower()),
                    source=str(cfg_path),
                    notes=f"instance model_path ({backend})",
                )
            )
        deep = cfg.get("deep_think") if isinstance(cfg.get("deep_think"), dict) else {}
        coder = str(deep.get("coder_model") or "").strip()
        if coder:
            _push(
                model_entry(
                    id=coder,
                    label=coder,
                    location="local",
                    provider="local",
                    in_use=False,
                    source=str(cfg_path) + "#deep_think",
                    notes="deep_think.coder_model",
                )
            )
        external = cfg.get("external_model") if isinstance(cfg.get("external_model"), dict) else {}
        if external.get("enabled"):
            ext_model = str(external.get("model") or "").strip()
            ext_prov = str(external.get("provider") or "external").strip()
            if ext_model:
                _push(
                    model_entry(
                        id=ext_model,
                        label=ext_model,
                        location=infer_model_location(ext_prov, ext_model),
                        provider=ext_prov,
                        in_use=False,
                        source=str(cfg_path) + "#external_model",
                        notes=f"external_model @ {external.get('base_url') or ''}".strip(),
                    )
                )
            providers.append(
                {
                    "id": ext_prov,
                    "label": ext_prov,
                    "status": "configured",
                    "source": str(cfg_path),
                    "notes": "external_model.enabled",
                }
            )
        providers.append(
            {
                "id": "local",
                "label": "Local GGUF / llama.cpp",
                "status": "configured",
                "source": str(cfg_path),
                "notes": backend,
            }
        )
        break  # first home with instance config wins for providers

    # Installed GGUF packages
    for m in list_jaeger_installed_gguf():
        _push(m)

    # Local ollama as optional provider for JROS external setups
    ollama_models = list_ollama_local_models()
    if ollama_models:
        providers.append(
            {
                "id": "ollama",
                "label": "Ollama (local daemon)",
                "status": "configured",
                "source": "http://127.0.0.1:11434/api/tags",
                "notes": f"{len(ollama_models)} model(s)",
            }
        )

    # de-dupe providers
    prov_map: dict[str, dict[str, Any]] = {}
    for p in providers:
        prov_map[p["id"]] = p
    if live_provider and live_provider not in prov_map:
        prov_map[live_provider] = {
            "id": live_provider,
            "label": live_provider,
            "status": "configured",
            "source": "jros_gateway",
            "notes": "active gateway provider",
        }

    return {
        "models": models,
        "providers": sorted(prov_map.values(), key=lambda p: p["id"]),
        "default": {
            "model": live_model or None,
            "provider": live_provider or "local",
            "instance": inst,
        },
    }


# ── CLI Adapter Model Discovery (Phase 2) ──


def discover_claude_models(claude_home: str | None = None) -> dict[str, Any]:
    """Claude Code configured model from env/settings.json/~/.claude.json."""
    from core.memory.journal.paths import claude_home as default_claude_home

    home = Path(claude_home or default_claude_home())
    models: list[dict[str, Any]] = []

    # Check env first (highest precedence)
    env_model = (os.environ.get("ANTHROPIC_MODEL") or "").strip()
    if env_model:
        models.append(
            model_entry(
                id=env_model,
                label=env_model,
                location="cloud",
                provider="anthropic",
                in_use=True,
                source="ANTHROPIC_MODEL env",
            )
        )
        return {"models": models}

    # Check project settings.json
    project_settings = _safe_json_load(home / "settings.json")
    project_model = (str(project_settings.get("model") or "")).strip()
    if project_model:
        models.append(
            model_entry(
                id=project_model,
                label=project_model,
                location="cloud",
                provider="anthropic",
                in_use=True,
                source=str(home / "settings.json"),
            )
        )
        return {"models": models}

    # Check global settings ~/.claude.json
    global_settings = _safe_json_load(Path.home() / ".claude.json")
    global_model = (str(global_settings.get("model") or "")).strip()
    if global_model:
        models.append(
            model_entry(
                id=global_model,
                label=global_model,
                location="cloud",
                provider="anthropic",
                in_use=True,
                source=str(Path.home() / ".claude.json"),
            )
        )
        return {"models": models}

    # Documented aliases (real, vendor-published, not synthetic IDs)
    for alias in ("opus", "sonnet", "haiku"):
        models.append(
            model_entry(
                id=alias,
                label=f"claude-{alias}",
                location="cloud",
                provider="anthropic",
                in_use=False,
                source="documented CLI alias",
                notes="Documented Claude Code alias, not live-verified",
            )
        )

    return {"models": models}


def discover_codex_models(codex_home: str | None = None) -> dict[str, Any]:
    """Codex configured models from config.toml (profile-aware)."""
    from core.memory.journal.paths import codex_dir
    import tomllib

    home = Path(codex_home or codex_dir())
    config_path = home / "config.toml"
    models: list[dict[str, Any]] = []

    if not config_path.is_file():
        return {"models": models}

    try:
        with config_path.open("rb") as fh:
            cfg = tomllib.load(fh)
    except Exception:
        logger.debug("Failed to parse %s", config_path, exc_info=True)
        return {"models": models}

    # Top-level model
    top_model = (str(cfg.get("model") or "")).strip()
    if top_model:
        models.append(
            model_entry(
                id=top_model,
                label=top_model,
                location=infer_model_location(None, top_model),
                provider=None,
                in_use=True,
                source=str(config_path),
            )
        )

    # Per-profile models
    profiles = cfg.get("profiles") or {}
    if isinstance(profiles, dict):
        for pname, pdata in profiles.items():
            if not isinstance(pdata, dict):
                continue
            pmodel = (str(pdata.get("model") or "")).strip()
            if pmodel:
                models.append(
                    model_entry(
                        id=pmodel,
                        label=pmodel,
                        location=infer_model_location(None, pmodel),
                        provider=None,
                        in_use=False,
                        source=str(config_path),
                        notes=f"profile: {pname}",
                    )
                )

    return {"models": models}


def discover_gemini_local_models(gemini_home: str | None = None) -> dict[str, Any]:
    """Gemini local configured model from env/settings.json."""
    from core.memory.journal.paths import gemini_home as default_gemini_home

    home = Path(gemini_home or default_gemini_home())
    models: list[dict[str, Any]] = []

    # Check env first
    env_model = (os.environ.get("GEMINI_MODEL") or "").strip()
    if env_model:
        models.append(
            model_entry(
                id=env_model,
                label=env_model,
                location="cloud",
                provider="google",
                in_use=True,
                source="GEMINI_MODEL env",
            )
        )
        return {"models": models}

    # Check settings.json
    settings = _safe_json_load(home / "settings.json")
    settings_model = (str(settings.get("model") or "")).strip()
    if settings_model:
        models.append(
            model_entry(
                id=settings_model,
                label=settings_model,
                location="cloud",
                provider="google",
                in_use=True,
                source=str(home / "settings.json"),
            )
        )

    return {"models": models}


def discover_opencode_models(cli_path: str = "opencode") -> dict[str, Any]:
    """OpenCode models via `opencode models` subcommand."""
    import subprocess

    models: list[dict[str, Any]] = []

    try:
        result = subprocess.run(
            [cli_path, "models"],
            capture_output=True,
            text=True,
            timeout=5,
            env={**os.environ, "NO_COLOR": "1"},  # Disable color codes
        )
        if result.returncode != 0:
            logger.debug("opencode models returned %d: %s", result.returncode, result.stderr)
            return {"models": models}

        for line in (result.stdout or "").strip().split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Expected format: "provider/model" or just "model"
            if "/" in line:
                provider, model_id = line.split("/", 1)
                model_id = model_id.strip()
                provider = provider.strip()
            else:
                model_id = line
                provider = None

            if model_id:
                models.append(
                    model_entry(
                        id=model_id,
                        label=model_id,
                        location=infer_model_location(provider, model_id),
                        provider=provider,
                        in_use=False,
                        source=f"{cli_path} models",
                    )
                )
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        logger.debug("Failed to run opencode models", exc_info=True)

    return {"models": models}


def discover_grok_models(grok_home: str | None = None) -> dict[str, Any]:
    """Grok models from ~/.grok/models_cache.json (xAI official CLI)."""
    home = Path(grok_home or os.environ.get("GROK_HOME") or Path.home() / ".grok")
    cache_path = home / "models_cache.json"
    models: list[dict[str, Any]] = []

    cache = _safe_json_load(cache_path)
    if not cache:
        return {"models": models}

    for item in cache.get("models") or []:
        if not isinstance(item, dict):
            continue
        model_id = str(item.get("id") or item.get("model") or "").strip()
        if not model_id:
            continue
        models.append(
            model_entry(
                id=model_id,
                label=model_id,
                location="cloud",
                provider="xai",
                in_use=False,
                source=str(cache_path),
            )
        )

    if not models:
        logger.debug("No models found in %s", cache_path)

    return {"models": models}


def discover_cursor_local_models() -> dict[str, Any]:
    """Cursor CLI not installed on this machine; placeholder returning honest empty state."""
    # Cursor CLI binary name and model-list subcommand are not yet verified.
    # Once installed, a spike should determine the real interface before implementation.
    return {
        "models": [
            model_entry(
                id="cursor-unknown",
                label="(Cursor CLI not detected)",
                location=None,
                provider=None,
                in_use=False,
                source="model_discovery.discover_cursor_local_models",
                notes="Cursor CLI not detected; model discovery not yet implemented — spike once a real install is available",
            )
        ]
    }


def discover_pi_local_models() -> dict[str, Any]:
    """Pi Coding Agent delegates to Ollama (hardcoded in _build_args)."""
    # Note: PiLocalBackend._build_args() unconditionally passes --provider ollama,
    # indicating Pi's models ARE Ollama's installed models. If Pi ever supports
    # other providers, this delegation should be revisited.
    ollama_models = list_ollama_local_models()
    return {"models": ollama_models}
