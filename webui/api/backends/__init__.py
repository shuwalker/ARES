"""
ARES Backends Package

This package provides the adapter layer so ARES can treat Hermes and JROS
as peer full agentic frameworks. All code here is ARES-owned.

Public exports:
    - get_router()
    - AgenticBackend, BackendRouter
    - HermesBackend, JROSBackend
"""

from .base import AgenticBackend, BackendRouter
from .hermes import HermesBackend
from .jros import JROSBackend
from .router import get_router, get_default_router

__all__ = [
    "AgenticBackend",
    "BackendRouter",
    "HermesBackend",
    "JROSBackend",
    "get_router",
    "get_default_router",
]
