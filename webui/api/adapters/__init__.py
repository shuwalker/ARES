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
from .aiavatar_adapter import AIAvatarAdapter
from .governance_adapter import GovernanceAdapter
from .vtuber_adapter import VTuberAdapter
from .minecraft_adapter import MinecraftAdapter
from .openwebui_adapter import OpenWebUIAdapter
from .worldview_adapter import WorldviewAdapter
from .bambu_adapter import BambuAdapter
from .sora_adapter import SoraAdapter
from .nina_adapter import NINAAdapter

__all__ = [
    "AdapterDeviceError",
    "AIAvatarAdapter",
    "AlpacaDeviceAdapter",
    "AstronomyService",
    "BambuAdapter",
    "BaseDeviceAdapter",
    "DeviceCapability",
    "DeviceConnectionState",
    "DeviceDescriptor",
    "DeviceDiscoveryService",
    "GovernanceAdapter",
    "INDIDeviceAdapter",
    "MinecraftAdapter",
    "NINAAdapter",
    "OpenWebUIAdapter",
    "SoraAdapter",
    "VTuberAdapter",
    "WorldviewAdapter",
]