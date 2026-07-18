"""ARES Backends Package

Flat registry of agnostic backends. Each backend is {name}_{deployment}.
No roles, no opinions. Paperclip pattern.
"""
from .base import AgenticBackend
from .hermes import HermesBackend
from .jros import JROSBackend
from .cli_backends import (
    AntigravityGeminiBackend,
    ClaudeLocalBackend,
    CodexLocalBackend,
    CursorAppBackend,
    CursorLocalBackend,
    GeminiLocalBackend,
    GrokLocalBackend,
    OllamaLocalBackend,
    OpenAICloudBackend,
    OpenCodeAppBackend,
    OpenCodeLocalBackend,
    PiLocalBackend,
    XAICloudBackend,
)
from .gemini_cloud import GeminiCloudBackend
from .ollama_hatchery import HatchedSIBackend, hatchery_autoload
from .router import get_router, get_default_router, BackendRouter

__all__ = [
    "AgenticBackend",
    "BackendRouter",
    "HermesBackend",
    "JROSBackend",
    "HatchedSIBackend",
    "AntigravityGeminiBackend",
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
    "get_router",
    "get_default_router",
    "hatchery_autoload",
]