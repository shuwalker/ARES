"""ARES Backends Package

Flat registry of agnostic backends. Each backend is {name}_{deployment}.
No roles, no opinions. Paperclip pattern.
"""
from .base import AgenticBackend
from .hermes import HermesBackend
from .jros import JROSBackend
from .cli_backends import (
    ClaudeLocalBackend,
    CodexLocalBackend,
    CursorLocalBackend,
    GeminiLocalBackend,
    GrokLocalBackend,
    OllamaLocalBackend,
    OpenAICloudBackend,
    OpenCodeLocalBackend,
    PiLocalBackend,
    XAICloudBackend,
)
from .ollama_hatchery import HatchedSIBackend, hatchery_autoload
from .router import get_router, get_default_router, BackendRouter

__all__ = [
    "AgenticBackend",
    "BackendRouter",
    "HermesBackend",
    "JROSBackend",
    "HatchedSIBackend",
    "ClaudeLocalBackend",
    "CodexLocalBackend",
    "CursorLocalBackend",
    "GeminiLocalBackend",
    "GrokLocalBackend",
    "OllamaLocalBackend",
    "OpenAICloudBackend",
    "OpenCodeLocalBackend",
    "PiLocalBackend",
    "XAICloudBackend",
    "get_router",
    "get_default_router",
    "hatchery_autoload",
]