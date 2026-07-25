"""JaegerAI onboarding API endpoints."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException
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
    """Model recommendation based on host tier."""
    registry_key: str
    display_name: str
    size_gb: float
    score_pct: float
    tokens_per_task: int
    notes: str


class ModelListResponse(BaseModel):
    """Response for available models."""
    awake: ModelRecommendation
    asleep: ModelRecommendation
    discovered: List[Dict[str, Any]]


class OnboardingCompleteRequest(BaseModel):
    """Request to complete JaegerAI onboarding."""
    character_id: str
    agent_name: str
    role: str
    awake_model: str
    asleep_model: str | None = None
    voice_id: str | None = None


@router.get("/characters", response_model=CharacterListResponse)
async def list_jaeger_characters() -> CharacterListResponse:
    """List all available JaegerAI characters for onboarding.
    
    Reads character.yaml files from the JaegerAI installation directory.
    """
    # Try multiple possible JaegerAI locations
    jaeger_paths = [
        Path.home() / "jaeger" / "jaeger_os" / "personality" / "characters",
        Path.home() / "GitHub" / "JaegerAI" / "jaeger_ai" / "personality" / "characters",
        Path.home() / ".jaeger" / "personality" / "characters",
    ]
    
    characters_root = None
    for path in jaeger_paths:
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
            identity = data.get("identity", {})
            
            characters.append(CharacterInfo(
                id=char_dir.name,
                name=data.get("name", char_dir.name),
                description=data.get("description", ""),
                role=identity.get("role", ""),
                voice_tone=identity.get("voice_tone", ""),
                voice_id=identity.get("voice_id", ""),
            ))
        except Exception as e:
            logger.warning(f"Failed to load character {char_dir.name}: {e}")
            continue
    
    return CharacterListResponse(characters=characters)


@router.get("/models", response_model=ModelListResponse)
async def get_jaeger_model_recommendations() -> ModelListResponse:
    """Get model recommendations for JaegerAI instance.
    
    Returns awake/asleep recommendations based on host hardware,
    plus any locally discovered GGUF files.
    """
    try:
        from jaeger_ai.core.models.host_recommendation import (
            detect_total_memory_gb,
            classify_tier,
            recommend_for_tier,
        )
        from jaeger_ai.core.models.local_discovery import (
            discover_local_gguf_files,
            match_to_registry,
        )
        from jaeger_ai.core.models.model_resolver import MODEL_REGISTRY
        
        # Detect host tier and get recommendations
        total_memory = detect_total_memory_gb()
        tier = classify_tier(total_memory)
        recs = recommend_for_tier(tier)
        
        # Get awake recommendation
        awake_entry = recs.get("awake")
        if not awake_entry:
            awake_entry = MODEL_REGISTRY.get("gemma3:27b-mlx")
        
        # Get asleep recommendation
        asleep_entry = recs.get("asleep")
        if not asleep_entry:
            asleep_entry = MODEL_REGISTRY.get("gemma4:31b-mlx")
        
        # Discover local GGUF files
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
        )
    except Exception as e:
        logger.error(f"Failed to get model recommendations: {e}")
        # Return defaults
        return ModelListResponse(
            awake=ModelRecommendation(
                registry_key="gemma3:27b-mlx",
                display_name="Gemma 3 27B",
                size_gb=18.0,
                score_pct=85.0,
                tokens_per_task=4096,
                notes="Default recommendation",
            ),
            asleep=ModelRecommendation(
                registry_key="gemma4:31b-mlx",
                display_name="Gemma 4 31B",
                size_gb=22.0,
                score_pct=90.0,
                tokens_per_task=8192,
                notes="Default recommendation",
            ),
            discovered=[],
        )


@router.post("/create-instance")
async def create_jaeger_instance(request: OnboardingCompleteRequest) -> Dict[str, Any]:
    """Create a new JaegerAI instance with the specified configuration.
    
    This calls the JaegerAI setup wizard programmatically to create
    the instance directory with identity.yaml, config.yaml, and soul.md.
    """
    try:
        from jaeger_ai.core.instance.setup_wizard import run_wizard
        from jaeger_ai.core.instance.instance import resolve_instance_dir
        
        # Check if instance already exists
        instance_name = request.agent_name.lower().replace(" ", "_").replace("-", "_")
        instance_dir = resolve_instance_dir(instance_name)
        
        if instance_dir.exists():
            raise HTTPException(
                status_code=400,
                detail=f"Instance '{instance_name}' already exists at {instance_dir}"
            )
        
        # Run the wizard programmatically
        # Note: This needs to be adapted to work non-interactively
        # For now, we'll create the instance files directly
        
        from jaeger_ai.core.instance.schemas import (
            Identity, Config, Manifest, SCHEMA_VERSION,
            ModelConfig, PermissionsConfig, InteractionConfig,
            SkillsConfig, WarmupConfig, RetentionConfig,
            DistributionConfig, DisplayConfig,
            dump_yaml,
        )
        
        # Create identity
        identity = Identity(
            display_name=request.agent_name,
            role=request.role,
            personality=f"Plays the {request.character_id} character.",
        )
        
        # Create config with models
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
        
        # Create manifest
        manifest = Manifest(
            schema_version=SCHEMA_VERSION,
            name=instance_name,
            created_by="ares-webui-onboarding",
        )
        
        # Create instance directory
        instance_dir.mkdir(parents=True, exist_ok=True)
        
        # Write files
        (instance_dir / "identity.yaml").write_text(
            dump_yaml(identity.model_dump()),
            encoding="utf-8"
        )
        (instance_dir / "config.yaml").write_text(
            dump_yaml(config.model_dump()),
            encoding="utf-8"
        )
        (instance_dir / "manifest.json").write_text(
            manifest.model_dump_json(indent=2),
            encoding="utf-8"
        )
        
        # Initialize git repo for versioning
        import subprocess
        try:
            subprocess.run(
                ["git", "init"],
                cwd=instance_dir,
                capture_output=True,
                timeout=10,
            )
        except Exception as e:
            logger.warning(f"Failed to init git repo: {e}")
        
        logger.info(f"Created JaegerAI instance '{instance_name}' at {instance_dir}")
        
        return {
            "success": True,
            "instance_name": instance_name,
            "instance_path": str(instance_dir),
            "character": request.character_id,
        }
        
    except ImportError as e:
        logger.error(f"JaegerAI not available: {e}")
        raise HTTPException(
            status_code=503,
            detail="JaegerAI is not installed or not accessible"
        )
    except Exception as e:
        logger.error(f"Failed to create JaegerAI instance: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create instance: {str(e)}"
        )


@router.get("/status")
async def get_jaeger_status() -> Dict[str, Any]:
    """Check JaegerAI installation and instance status."""
    import shutil
    
    # Check if jaeger CLI is available
    jaeger_cli = shutil.which("jaeger")
    
    # Check for JaegerAI Python module
    try:
        import jaeger_ai
        jaeger_ai_available = True
        jaeger_ai_path = str(Path(jaeger_ai.__file__).parent.parent)
    except ImportError:
        jaeger_ai_available = False
        jaeger_ai_path = None
    
    # Check for existing instances
    instance_dirs = [
        Path.home() / "jaeger" / "jaeger_os" / "instances",
        Path.home() / ".jaeger" / "instances",
        Path.home() / "GitHub" / "JaegerAI" / "instances",
    ]
    
    instances = []
    for instances_dir in instance_dirs:
        if instances_dir.is_dir():
            for instance_dir in instances_dir.iterdir():
                if instance_dir.is_dir() and (instance_dir / "identity.yaml").exists():
                    import yaml
                    identity = yaml.safe_load((instance_dir / "identity.yaml").read_text())
                    instances.append({
                        "name": instance_dir.name,
                        "path": str(instance_dir),
                        "display_name": identity.get("display_name", instance_dir.name),
                    })
    
    return {
        "jaeger_cli": jaeger_cli,
        "jaeger_ai_available": jaeger_ai_available,
        "jaeger_ai_path": jaeger_ai_path,
        "instances": instances,
        "has_instances": len(instances) > 0,
    }
