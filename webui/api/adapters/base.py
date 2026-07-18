"""Strict device adapter contracts for astronomical equipment control.

Device adapters translate ARES astronomy requests into protocol-specific calls
(INDI XML, Alpaca REST, etc.).  They manage connection lifecycle, expose device
capabilities, and report health — mirroring the BaseConnectionAdapter pattern
used by LLM and tool adapters.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class AdapterDeviceError(RuntimeError):
    """A bounded, user-safe device adapter failure."""

    def __init__(
        self,
        status_code: int,
        message: str,
        *,
        code: str = "device_error",
        context: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.code = code
        self.context = dict(context or {})


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class DeviceCapability(Enum):
    """Stable ARES device capability identifiers."""

    TELESCOPE = "telescope"
    CAMERA = "camera"
    FOCUSER = "focuser"
    FILTER_WHEEL = "filter_wheel"
    DOME = "dome"
    SWITCH = "switch"
    WEATHER = "weather"
    GPS = "gps"
    ROTATOR = "rotator"
    SAFETY_MONITOR = "safety_monitor"
    PLATESOLVER = "platesolver"


class DeviceConnectionState(Enum):
    """Device connection lifecycle states."""

    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    ERROR = "error"


# ---------------------------------------------------------------------------
# Data descriptors
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DeviceHealth:
    """Normalized health report for a device adapter."""

    state: DeviceConnectionState
    available: bool
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "state": self.state.value,
            "available": self.available,
            "message": self.message,
            "details": dict(self.details),
        }


@dataclass(frozen=True)
class DeviceDescriptor:
    """Describes a discovered or connected device."""

    device_id: str
    name: str
    driver: str
    capability: DeviceCapability
    adapter_kind: str  # "indi" | "alpaca"
    connection_state: DeviceConnectionState = DeviceConnectionState.DISCONNECTED
    properties: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "device_id": self.device_id,
            "name": self.name,
            "driver": self.driver,
            "capability": self.capability.value,
            "adapter_kind": self.adapter_kind,
            "connection_state": self.connection_state.value,
            "properties": dict(self.properties),
        }


# ---------------------------------------------------------------------------
# Abstract base
# ---------------------------------------------------------------------------

class BaseDeviceAdapter(ABC):
    """Common contract for astronomical device adapters.

    Subclasses implement ``connect``, ``disconnect``, ``health``,
    ``capabilities``, ``device_info``, and device-specific operations.
    """

    adapter_id: str
    display_name: str
    kind: str  # "indi" | "alpaca"

    @abstractmethod
    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Open a connection to *device_id* and return its descriptor.

        Raises:
            AdapterDeviceError: If the connection cannot be established.
        """

    @abstractmethod
    async def disconnect(self, device_id: str) -> None:
        """Gracefully close the connection to *device_id*.

        Should be idempotent — calling disconnect on an already-disconnected
        device must not raise.
        """

    @abstractmethod
    def health(self, device_id: str) -> DeviceHealth:
        """Return a normalized, non-secret connection state for *device_id*."""

    @abstractmethod
    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return the stable ARES capability identifiers for *device_id*."""

    @abstractmethod
    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """

    @abstractmethod
    async def discover(self) -> list[DeviceDescriptor]:
        """Probe the network for devices this adapter can control.

        Returns zero or more ``DeviceDescriptor`` instances representing
        reachable devices, regardless of connection state.
        """

    def connection_record(self, device_id: str) -> dict[str, Any]:
        """Compose a JSON-safe record combining health, capabilities, and info."""
        info = self.device_info(device_id)
        return {
            **info.as_dict(),
            "health": self.health(device_id).as_dict(),
            "capabilities": [c.value for c in self.capabilities(device_id)],
        }

    def all_connection_records(self) -> list[dict[str, Any]]:
        """Return connection records for all known devices."""
        # Default: subclasses override with richer discovery
        return []