"""ARES device adapter framework — INDI, Alpaca, and discovery layer."""

from .base import (
    AdapterDeviceError,
    BaseDeviceAdapter,
    DeviceCapability,
    DeviceConnectionState,
    DeviceDescriptor,
    DeviceHealth,
)
from .discovery import DeviceDiscoveryService
from .indi_adapter import INDIDeviceAdapter
from .alpaca_adapter import AlpacaDeviceAdapter
from .astronomy_service import AstronomyService

__all__ = [
    "AdapterDeviceError",
    "AlpacaDeviceAdapter",
    "AstronomyService",
    "BaseDeviceAdapter",
    "DeviceCapability",
    "DeviceConnectionState",
    "DeviceDescriptor",
    "DeviceDiscoveryService",
    "INDIDeviceAdapter",
]