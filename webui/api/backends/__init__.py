"""ARES Backends Package

Flat registry of agnostic backends. Each backend is {name}_{deployment}.
No roles, no opinions. Paperclip pattern.

Backends register themselves via BackendRegistry at import time.
The router queries the registry for available backends.
"""
from api.providers.agentic_backend import AgenticBackend
from api.providers.hermes.backend import HermesBackend
from api.providers.jaeger.backend import JROSBackend
from .cli_backends import (
    AntigravityGeminiBackend,
    BackendRegistry,
    ClaudeCloudBackend,
    CursorAppBackend,
    OllamaLocalBackend,
    OpenAICloudBackend,
    OpenCodeAppBackend,
    XAICloudBackend,
)
from .cli_backends_legacy import (
    ClaudeLocalBackend,
    CodexLocalBackend,
    CursorLocalBackend,
    GeminiLocalBackend,
    GrokLocalBackend,
    OpenCodeLocalBackend,
    PiLocalBackend,
)
from .gemini_cloud import GeminiCloudBackend
from .ollama_hatchery import HatchedSIBackend, hatchery_autoload
from .router import get_router, get_default_router, BackendRouter

__all__ = [
    "AgenticBackend",
    "BackendRegistry",
    "BackendRouter",
    "HermesBackend",
    "JROSBackend",
    "HatchedSIBackend",
    "ClaudeCloudBackend",
    "ClaudeLocalBackend",
    "CodexLocalBackend",
    "CursorAppBackend",
    "CursorLocalBackend",
    "GeminiCloudBackend",
    "GeminiLocalBackend",
    "GrokLocalBackend",
    "OllamaLocalBackend",
    "OpenAICloudBackend",
    "OpenCodeAppBackend",
    "OpenCodeLocalBackend",
    "PiLocalBackend",
    "XAICloudBackend",
    "AntigravityGeminiBackend",
    "get_router",
    "get_default_router",
    "hatchery_autoload",
]