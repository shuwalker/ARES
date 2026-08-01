"""JaegerAI onboarding and peer-runtime status API endpoints.

JaegerAI is a peer product, not an in-process ARES library. Status probes use
the shared provider contract in ``api.providers.jaeger.status`` so Settings and
Control Center report the same truth as chat routing.
"""

from __future__ import annotations

import logging
import shutil
import time
from pathlib import Path
from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/jaeger-onboarding", tags=["jaeger-onboarding"])


class CharacterInfo(BaseModel):
    """Character metadata for onboarding UI."""

    id: str
    name: str
    description: str
    role: str
    voice_tone: str
    voice_id: str


class CharacterListResponse(BaseModel):
    """Response for listing available JaegerAI characters."""

    characters: List[CharacterInfo]


class ModelRecommendation(BaseModel):
    """Model recommendation based on host tier.

    WARNING for UI consumers: these are *recommendations*, not installed or
    active models. Never display them as the current runtime model.
    """

    registry_key: str
    display_name: str
    size_gb: float
    score_pct: float
    tokens_per_task: int
    notes: str


class ModelListResponse(BaseModel):
    """Response for model recommendations (not live active-model state)."""

    awake: ModelRecommendation
    asleep: ModelRecommendation
    discovered: List[Dict[str, Any]]
    #: Explicit flag so clients never treat recommendations as live inventory.
    recommendations_only: bool = True


class OnboardingCompleteRequest(BaseModel):
    """Request to complete JaegerAI onboarding."""

    character_id: str
    agent_name: str
    role: str
    awake_model: str
    asleep_model: str | None = None
    voice_id: str | None = None


def _character_search_roots() -> list[Path]:
    """Portable character roots — env overrides first, no maintainer paths required."""
    roots: list[Path] = []
    for env_name in ("ARES_CHARACTER_DIR", "ARES_PERSONA_DIR", "ARES_JAEGER_HOME", "JAEGER_HOME"):
        raw = __import__("os").environ.get(env_name, "").strip()
        if not raw:
            continue
        base = Path(raw).expanduser()
        roots.extend(
            [
                base / "personality" / "characters",
                base / "jaeger_os" / "personality" / "characters",
                base / "jaeger_ai" / "personality" / "characters",
            ]
        )
    # Installed peer defaults (portable; not maintainer-specific).
    home = Path.home()
    roots.extend(
        [
            home / "jaeger" / "jaeger_os" / "personality" / "characters",
            home / ".jaeger" / "personality" / "characters",
        ]
    )
    return roots


def _instance_search_roots() -> list[Path]:
    roots: list[Path] = []
    for env_name in ("ARES_JAEGER_HOME", "JAEGER_HOME", "JAEGER_INSTANCE_DIR"):
        raw = __import__("os").environ.get(env_name, "").strip()
        if not raw:
            continue
        base = Path(raw).expanduser()
        if env_name == "JAEGER_INSTANCE_DIR":
            roots.append(base.parent if base.name else base)
        else:
            roots.extend(
                [
                    base / ".jaeger_os" / "instances",
                    base / "instances",
                    base / "jaeger_os" / "instances",
                ]
            )
    home = Path.home()
    roots.extend(
        [
            home / "jaeger" / ".jaeger_os" / "instances",
            home / "jaeger" / "instances",
            home / ".jaeger" / "instances",
        ]
    )
    return roots


def _discover_instances() -> list[dict[str, Any]]:
    instances: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for instances_dir in _instance_search_roots():
        if not instances_dir.is_dir():
            continue
        try:
            children = list(instances_dir.iterdir())
        except OSError:
            continue
        for instance_dir in children:
            if not instance_dir.is_dir():
                continue
            identity_path = instance_dir / "identity.yaml"
            if not identity_path.exists():
                continue
            resolved = str(instance_dir.resolve())
            if resolved in seen_paths:
                continue
            seen_paths.add(resolved)
            display_name = instance_dir.name
            model = None
            character = None
            try:
                import yaml

                identity = yaml.safe_load(identity_path.read_text(encoding="utf-8")) or {}
                if isinstance(identity, dict):
                    display_name = str(identity.get("display_name") or display_name)
                    character = identity.get("personality") or identity.get("role")
                config_path = instance_dir / "config.yaml"
                if config_path.exists():
                    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
                    if isinstance(config, dict):
                        model_cfg = config.get("model") or {}
                        if isinstance(model_cfg, dict):
                            model = model_cfg.get("awake") or model_cfg.get("default")
            except Exception as exc:
                logger.debug("Failed to read Jaeger instance %s: %s", instance_dir, exc)
            instances.append(
                {
                    "name": instance_dir.name,
                    "path": resolved,
                    "display_name": display_name,
                    "model": model,
                    "character": character,
                }
            )
    return instances


@router.get("/characters", response_model=CharacterListResponse)
async def list_jaeger_characters() -> CharacterListResponse:
    """List available JaegerAI characters for onboarding."""
    characters_root = None
    for path in _character_search_roots():
        if path.is_dir():
            characters_root = path
            break

    if characters_root is None:
        logger.warning("JaegerAI characters directory not found")
        return CharacterListResponse(characters=[])

    characters = []
    for char_dir in sorted(characters_root.iterdir()):
        if not char_dir.is_dir():
            continue

        char_yaml = char_dir / "character.yaml"
        if not char_yaml.exists():
            continue

        try:
            import yaml

            data = yaml.safe_load(char_yaml.read_text(encoding="utf-8")) or {}
            identity = data.get("identity", {}) if isinstance(data, dict) else {}

            characters.append(
                CharacterInfo(
                    id=char_dir.name,
                    name=data.get("name", char_dir.name) if isinstance(data, dict) else char_dir.name,
                    description=str(data.get("description", "") if isinstance(data, dict) else ""),
                    role=str(identity.get("role", "") if isinstance(identity, dict) else ""),
                    voice_tone=str(identity.get("voice_tone", "") if isinstance(identity, dict) else ""),
                    voice_id=str(identity.get("voice_id", "") if isinstance(identity, dict) else ""),
                )
            )
        except Exception as e:
            logger.warning("Failed to load character %s: %s", char_dir.name, e)
            continue

    return CharacterListResponse(characters=characters)


@router.get("/models", response_model=ModelListResponse)
async def get_jaeger_model_recommendations() -> ModelListResponse:
    """Get model *recommendations* for JaegerAI (not live active models).

    When discovery fails, fallback recommendations are returned with
    ``recommendations_only=True``. UI must not label these as installed/active.
    """
    try:
        from jaeger_ai.core.models.host_recommendation import (
            classify_tier,
            detect_total_memory_gb,
            recommend_for_tier,
        )
        from jaeger_ai.core.models.local_discovery import (
            discover_local_gguf_files,
        )
        from jaeger_ai.core.models.model_resolver import MODEL_REGISTRY

        total_memory = detect_total_memory_gb()
        tier = classify_tier(total_memory)
        recs = recommend_for_tier(tier)

        awake_entry = recs.get("awake") or MODEL_REGISTRY.get("gemma3:27b-mlx")
        asleep_entry = recs.get("asleep") or MODEL_REGISTRY.get("gemma4:31b-mlx")

        discovered = discover_local_gguf_files()
        discovered_list = [
            {
                "path": str(d.path),
                "filename": d.filename,
                "size_gb": d.size_gb,
                "source": d.source,
            }
            for d in discovered
        ]

        return ModelListResponse(
            awake=ModelRecommendation(
                registry_key=awake_entry.registry_key if awake_entry else "gemma3:27b-mlx",
                display_name=awake_entry.display_name if awake_entry else "Gemma 3 27B",
                size_gb=awake_entry.size_gb if awake_entry else 18.0,
                score_pct=awake_entry.score_pct if awake_entry else 85.0,
                tokens_per_task=awake_entry.tokens_per_task if awake_entry else 4096,
                notes=awake_entry.notes if awake_entry else "Recommended for your hardware",
            ),
            asleep=ModelRecommendation(
                registry_key=asleep_entry.registry_key if asleep_entry else "gemma4:31b-mlx",
                display_name=asleep_entry.display_name if asleep_entry else "Gemma 4 31B",
                size_gb=asleep_entry.size_gb if asleep_entry else 22.0,
                score_pct=asleep_entry.score_pct if asleep_entry else 90.0,
                tokens_per_task=asleep_entry.tokens_per_task if asleep_entry else 8192,
                notes=asleep_entry.notes if asleep_entry else "Recommended for deep thinking",
            ),
            discovered=discovered_list,
            recommendations_only=True,
        )
    except Exception as e:
        logger.error("Failed to get model recommendations: %s", e)
        return ModelListResponse(
            awake=ModelRecommendation(
                registry_key="gemma3:27b-mlx",
                display_name="Gemma 3 27B",
                size_gb=18.0,
                score_pct=85.0,
                tokens_per_task=4096,
                notes="Default recommendation (discovery unavailable)",
            ),
            asleep=ModelRecommendation(
                registry_key="gemma4:31b-mlx",
                display_name="Gemma 4 31B",
                size_gb=22.0,
                score_pct=90.0,
                tokens_per_task=8192,
                notes="Default recommendation (discovery unavailable)",
            ),
            discovered=[],
            recommendations_only=True,
        )


@router.post("/create-instance")
async def create_jaeger_instance(request: OnboardingCompleteRequest) -> Dict[str, Any]:
    """Create a new JaegerAI instance with the specified configuration."""
    try:
        from jaeger_ai.core.instance.instance import resolve_instance_dir
        from jaeger_ai.core.instance.schemas import (
            SCHEMA_VERSION,
            Config,
            DisplayConfig,
            DistributionConfig,
            Identity,
            InteractionConfig,
            Manifest,
            ModelConfig,
            PermissionsConfig,
            RetentionConfig,
            SkillsConfig,
            WarmupConfig,
            dump_yaml,
        )

        instance_name = request.agent_name.lower().replace(" ", "_").replace("-", "_")
        instance_dir = resolve_instance_dir(instance_name)

        if instance_dir.exists():
            raise HTTPException(
                status_code=400,
                detail=f"Instance '{instance_name}' already exists at {instance_dir}",
            )

        identity = Identity(
            display_name=request.agent_name,
            role=request.role,
            personality=f"Plays the {request.character_id} character.",
        )

        config = Config(
            schema_version=SCHEMA_VERSION,
            model=ModelConfig(
                awake=request.awake_model,
                asleep=request.asleep_model if request.asleep_model else request.awake_model,
            ),
            permissions=PermissionsConfig(),
            interaction=InteractionConfig(),
            skills=SkillsConfig(),
            warmup=WarmupConfig(),
            retention=RetentionConfig(),
            distribution=DistributionConfig(),
            display=DisplayConfig(),
        )

        manifest = Manifest(
            schema_version=SCHEMA_VERSION,
            name=instance_name,
            created_by="ares-webui-onboarding",
        )

        instance_dir.mkdir(parents=True, exist_ok=True)

        (instance_dir / "identity.yaml").write_text(
            dump_yaml(identity.model_dump()),
            encoding="utf-8",
        )
        (instance_dir / "config.yaml").write_text(
            dump_yaml(config.model_dump()),
            encoding="utf-8",
        )
        (instance_dir / "manifest.json").write_text(
            manifest.model_dump_json(indent=2),
            encoding="utf-8",
        )

        import subprocess

        try:
            subprocess.run(
                ["git", "init"],
                cwd=instance_dir,
                capture_output=True,
                timeout=10,
                check=False,
            )
        except Exception as e:
            logger.warning("Failed to init git repo: %s", e)

        logger.info("Created JaegerAI instance '%s' at %s", instance_name, instance_dir)

        return {
            "success": True,
            "instance_name": instance_name,
            "instance_path": str(instance_dir),
            "character": request.character_id,
        }

    except ImportError as e:
        logger.error("JaegerAI not available: %s", e)
        raise HTTPException(
            status_code=503,
            detail="JaegerAI is not installed or not accessible",
        ) from e
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to create JaegerAI instance: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create instance: {str(e)}",
        ) from e


@router.get("/status")
async def get_jaeger_status(
    refresh: bool = Query(False, description="Bypass status cache and re-probe."),
) -> Dict[str, Any]:
    """Live JaegerAI peer status for Settings SI and diagnostics.

    Uses the shared provider status contract (gateway or local bridge) so the
    UI never invents "running" from a preference. Instance listing is best-effort
    filesystem discovery and is separate from transport readiness.
    """
    checked_at = time.time()
    jaeger_cli = shutil.which("jaeger")

    # Python package presence (install signal only — not runtime readiness).
    jaeger_ai_available = False
    jaeger_ai_path = None
    try:
        import jaeger_ai

        jaeger_ai_available = True
        jaeger_ai_path = str(Path(jaeger_ai.__file__).parent.parent)
    except ImportError:
        pass

    provider_state = "error"
    provider_available = False
    provider_message = "JaegerAI status could not be determined."
    provider_details: dict[str, Any] = {}
    try:
        from api.providers.jaeger.status import check_status, reset_cache

        if refresh:
            reset_cache()
        status = check_status(use_cache=not refresh)
        provider_state = status.state.value
        provider_available = bool(status.available)
        provider_message = status.message
        provider_details = dict(status.details or {})
    except Exception as exc:
        logger.debug("Provider status probe failed: %s", exc, exc_info=True)
        provider_state = "error"
        provider_available = False
        provider_message = f"JaegerAI status probe failed: {exc}"

    companion_ready = False
    try:
        from api.providers.jaeger.companion import companion_available

        companion_ready = bool(companion_available())
    except Exception:
        companion_ready = False

    instances = _discover_instances()

    # Map provider states onto explicit UI labels without collapsing failures.
    ui_state = {
        "connected": "ready",
        "needs_attention": "needs_attention",
        "offline": "installed_but_stopped",
        "not_installed": "not_installed",
        "not_configured": "misconfigured",
        "error": "error",
    }.get(provider_state, "unavailable")

    # Active model only when the live health probe reported one — never from
    # recommendation fallbacks.
    active_model = provider_details.get("model")
    active_instance = provider_details.get("instance")
    transport_mode = provider_details.get("mode")  # gateway | bridge
    gateway_url = provider_details.get("gateway_url")
    root = provider_details.get("root")

    return {
        "state": ui_state,
        "provider_state": provider_state,
        "available": provider_available,
        "message": provider_message,
        "details": provider_details,
        "checked_at": checked_at,
        "jaeger_cli": jaeger_cli,
        "jaeger_ai_available": jaeger_ai_available,
        "jaeger_ai_path": jaeger_ai_path,
        "companion_ready": companion_ready,
        "transport_mode": transport_mode,
        "gateway_url": gateway_url,
        "root": root,
        "active_model": active_model,
        "active_instance": active_instance,
        "instances": instances,
        "has_instances": len(instances) > 0,
        # Explicit non-recommendation marker for clients.
        "models_are_live": active_model is not None,
    }
