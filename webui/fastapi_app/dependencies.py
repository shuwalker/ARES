"""FastAPI dependency accessors."""

from fastapi import Request

from .adapters import AdapterRegistry
from .services import AresCoreService
from .realtime import RealtimeService


def get_core_service(request: Request) -> AresCoreService:
    return request.app.state.core_service


def get_realtime_service(request: Request) -> RealtimeService:
    return request.app.state.realtime_service


def get_adapter_registry(request: Request) -> AdapterRegistry:
    return request.app.state.adapter_registry
