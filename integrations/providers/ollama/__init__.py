"""Ollama local-model provider package."""
from __future__ import annotations

from .status import base_url, check_status, installed_models

__all__ = ["base_url", "check_status", "installed_models"]
