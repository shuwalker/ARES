"""ARES FastAPI connection adapters."""

from .base import (
    AdapterError,
    AdapterHealth,
    BaseConnectionAdapter,
    BaseLLMAdapter,
    BaseToolAdapter,
    ModelDescriptor,
    StreamSubscription,
)
from .frameworks import AresAdapter, HybridAdapter, JaegerAdapter
from .mcp import McpToolAdapter
from .registry import AdapterRegistry

__all__ = [
    "AdapterError",
    "AdapterHealth",
    "AdapterRegistry",
    "AresAdapter",
    "BaseConnectionAdapter",
    "BaseLLMAdapter",
    "BaseToolAdapter",
    "HybridAdapter",
    "JaegerAdapter",
    "McpToolAdapter",
    "ModelDescriptor",
    "StreamSubscription",
]
