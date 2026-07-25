"""
ARES Backends Package

This package exposes JaegerAI/JROS as ARES's conversation runtime.

Public exports:
    - get_router()
    - AgenticBackend, BackendRouter
    - JROSBackend
"""

from .base import AgenticBackend, BackendRouter
from .jros import JROSBackend
from .router import get_router, get_default_router

__all__ = [
    "AgenticBackend",
    "BackendRouter",
    "JROSBackend",
    "get_router",
    "get_default_router",
]
