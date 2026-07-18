"""ASCOM Alpaca REST device adapter.

Wraps the Alpaca REST API to control telescopes, cameras, focusers, and filter
wheels reachable via an Alpaca server (discovered by UDP broadcast or manually
configured).

Current status: **stub** — method bodies contain TODO markers where actual
Alpaca REST calls belong.  This lets the router and service layer wire up
end-to-end while the Alpaca integration is still in progress.
"""

from __future__ import annotations

import logging
from typing import Any

from .base import (
    AdapterDeviceError,
    BaseDeviceAdapter,
    DeviceCapability,
    DeviceConnectionState,
    DeviceDescriptor,
    DeviceHealth,
)

logger = logging.getLogger(__name__)

# Default Alpaca server location
_DEFAULT_ALPACA_HOST = "localhost"
_DEFAULT_ALPACA_PORT = 11111


class AlpacaDeviceAdapter(BaseDeviceAdapter):
    """Device adapter for the ASCOM Alpaca REST protocol.

    Discovers devices advertised by an Alpaca server and exposes telescope,
    camera, focuser, and filter-wheel operations.

    Parameters:
        host: Alpaca server hostname or IP.
        port: Alpaca server port.
    """

    adapter_id = "alpaca"
    display_name = "Alpaca"
    kind = "alpaca"

    def __init__(
        self,
        host: str = _DEFAULT_ALPACA_HOST,
        port: int = _DEFAULT_ALPACA_PORT,
    ) -> None:
        self._host = host
        self._port = port
        # TODO: initialise httpx.AsyncClient for Alpaca REST calls
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to an Alpaca device by its Alpaca device identifier.

        TODO: Call ``PUT /api/v1/{device_type}/{device_number}/connected``
        with ``Connected=true``, then verify with a GET.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info(
            "Connecting to Alpaca device %s at %s:%d", device_id, self._host, self._port,
        )

        # TODO: Replace with actual Alpaca REST connect:
        #   await self._client.put(f"http://{host}:{port}/api/v1/{device_type}/{device_number}/connected", ...)
        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from Alpaca /api/v1/{type}/{n}/name
            driver="alpaca_unknown",
            capability=DeviceCapability.TELESCOPE,  # TODO: classify from Alpaca device type
            adapter_kind="alpaca",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from an Alpaca device.

        TODO: Call ``PUT /api/v1/{device_type}/{device_number}/connected``
        with ``Connected=false``.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Alpaca device %s", device_id)
        # TODO: await self._client.put(...)
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report device health by checking Alpaca connected state.

        TODO: Call ``GET /api/v1/{device_type}/{device_number}/connected``.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="Device connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Device disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return capabilities based on the Alpaca device type.

        TODO: Map Alpaca device types (``telescope``, ``camerav2``, etc.)
        to ``DeviceCapability`` values.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from Alpaca device type
        return [DeviceCapability.TELESCOPE]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current device descriptor.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Alpaca device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover devices advertised by the Alpaca server.

        TODO: Call ``GET /api/v1/{device_type}`` for each known Alpaca
        device type, then build a ``DeviceDescriptor`` per discovered device.
        """
        logger.info("Discovering Alpaca devices at %s:%d", self._host, self._port)
        # TODO: await self._client.get(f"http://{host}:{port}/api/v1/telescope/0", ...)
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Telescope operations
    # ------------------------------------------------------------------

    async def telescope_goto(self, device_id: str, ra: float, dec: float) -> dict[str, Any]:
        """Slew the telescope to the given RA/Dec.

        TODO: ``PUT /api/v1/telescope/{n}/slewtocoordinates``.
        """
        self._require_connected(device_id)
        logger.info("Telescope GOTO %s: ra=%.4f dec=%.4f", device_id, ra, dec)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "goto", "ra": ra, "dec": dec, "status": "slewing"}

    async def telescope_sync(self, device_id: str, ra: float, dec: float) -> dict[str, Any]:
        """Sync the telescope position.

        TODO: ``PUT /api/v1/telescope/{n}/syncsynchronize``.
        """
        self._require_connected(device_id)
        logger.info("Telescope SYNC %s: ra=%.4f dec=%.4f", device_id, ra, dec)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "sync", "ra": ra, "dec": dec, "status": "synced"}

    async def telescope_park(self, device_id: str) -> dict[str, Any]:
        """Park the telescope.

        TODO: ``PUT /api/v1/telescope/{n}/park``.
        """
        self._require_connected(device_id)
        logger.info("Telescope PARK %s", device_id)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "park", "status": "parking"}

    async def telescope_tracking(self, device_id: str, enabled: bool) -> dict[str, Any]:
        """Enable or disable sidereal tracking.

        TODO: ``PUT /api/v1/telescope/{n}/tracking``.
        """
        self._require_connected(device_id)
        logger.info("Telescope TRACKING %s: %s", device_id, enabled)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "tracking", "enabled": enabled, "status": "ok"}

    # ------------------------------------------------------------------
    # Camera operations
    # ------------------------------------------------------------------

    async def camera_exposure(
        self, device_id: str, duration: float, *, frame_type: str = "Light",
    ) -> dict[str, Any]:
        """Start a camera exposure.

        TODO: ``PUT /api/v1/camera/{n}/startexposure``.
        """
        self._require_connected(device_id)
        logger.info("Camera EXPOSURE %s: %.1fs (%s)", device_id, duration, frame_type)
        # TODO: Alpaca REST call
        return {
            "device_id": device_id,
            "action": "exposure",
            "duration": duration,
            "frame_type": frame_type,
            "status": "exposing",
        }

    async def camera_abort(self, device_id: str) -> dict[str, Any]:
        """Abort the current camera exposure.

        TODO: ``PUT /api/v1/camera/{n}/abortexposure``.
        """
        self._require_connected(device_id)
        logger.info("Camera ABORT %s", device_id)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "abort", "status": "aborted"}

    async def camera_temperature(self, device_id: str) -> dict[str, Any]:
        """Read the camera sensor temperature.

        TODO: ``GET /api/v1/camera/{n}/ccdtemperature``.
        """
        self._require_connected(device_id)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "temperature_c": 0.0, "status": "stub"}

    # ------------------------------------------------------------------
    # Focuser operations
    # ------------------------------------------------------------------

    async def focuser_move(self, device_id: str, position: int) -> dict[str, Any]:
        """Move the focuser to an absolute position.

        TODO: ``PUT /api/v1/focuser/{n}/move``.
        """
        self._require_connected(device_id)
        logger.info("Focuser MOVE %s → %d", device_id, position)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "move", "position": position, "status": "moving"}

    async def focuser_auto_focus(self, device_id: str) -> dict[str, Any]:
        """Trigger an auto-focus run.

        TODO: ARES-specific focus-loop or Alpaca ``/api/v1/focuser/{n}/halt`` +
        iterative position sweeps.
        """
        self._require_connected(device_id)
        logger.info("Focuser AUTO-FOCUS %s", device_id)
        # TODO: Alpaca REST or focus-loop
        return {"device_id": device_id, "action": "auto_focus", "status": "running"}

    # ------------------------------------------------------------------
    # Filter wheel operations
    # ------------------------------------------------------------------

    async def filter_wheel_position(self, device_id: str, slot: int) -> dict[str, Any]:
        """Move the filter wheel to *slot* (0-indexed).

        TODO: ``PUT /api/v1/filterwheel/{n}/position``.
        """
        self._require_connected(device_id)
        logger.info("Filter WHEEL %s → slot %d", device_id, slot)
        # TODO: Alpaca REST call
        return {"device_id": device_id, "action": "change_filter", "slot": slot, "status": "moving"}

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _require_connected(self, device_id: str) -> None:
        """Raise ``AdapterDeviceError`` if the device is not connected."""
        if not self._connected.get(device_id):
            raise AdapterDeviceError(
                409,
                f"Device {device_id} is not connected",
                code="device_not_connected",
            )