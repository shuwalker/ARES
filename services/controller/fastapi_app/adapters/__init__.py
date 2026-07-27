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
from .frameworks import JaegerAdapter
from .mcp import McpToolAdapter
from .registry import AdapterRegistry

__all__ = [
    "AdapterError",
    "AdapterHealth",
    "AdapterRegistry",
    "BaseConnectionAdapter",
    "BaseLLMAdapter",
    "BaseToolAdapter",
    "JaegerAdapter",
    "McpToolAdapter",
    "ModelDescriptor",
    "StreamSubscription",
]
