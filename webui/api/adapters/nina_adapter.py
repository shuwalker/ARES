"""NINA / Alpaca adapter for astrophotography device control.

Connects to N.I.N.A. (Nighttime Imaging 'N' Astronomy) via its Alpaca
REST API to control astrophotography equipment — telescopes, cameras,
focusers, filter wheels, and other devices.  This complements the
existing INDI adapter by providing access to Windows-centric astronomy
gear through the ASCOM Alpaca protocol.

Current status: **stub** — method bodies contain TODO markers where
actual Alpaca REST calls belong.
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

_DEFAULT_ALPACA_HOST = "localhost"
_DEFAULT_ALPACA_PORT = 11111  # NINA Alpaca default


class NINAAdapter(BaseDeviceAdapter):
    """Device adapter for NINA (N.I.N.A.) via Alpaca REST API.

    Uses the ASCOM Alpaca REST protocol to communicate with NINA's
    built-in Alpaca server, enabling ARES to control telescopes,
    cameras, focusers, and filter wheels managed by NINA.

    Parameters:
        host: NINA Alpaca server hostname.
        port: NINA Alpaca server port.
    """

    adapter_id = "nina"
    display_name = "NINA (Alpaca)"
    kind = "alpaca"

    def __init__(
        self,
        host: str = _DEFAULT_ALPACA_HOST,
        port: int = _DEFAULT_ALPACA_PORT,
    ) -> None:
        self._host = host
        self._port = port
        # TODO: initialise httpx.AsyncClient for Alpaca REST calls
        # self._base_url = f"http://{host}:{port}/api/v1/"
        # self._http = httpx.AsyncClient(base_url=self._base_url)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to a NINA-managed device via Alpaca.

        TODO: PUT /api/v1/{device_type}/{device_number}/connected with
        Connected=true, verify response, and mark connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to NINA device %s at %s:%d", device_id, self._host, self._port)

        # TODO: Replace with actual Alpaca connect:
        #   resp = await self._http.put(f"/api/v1/telescope/0/connected", json={"Connected": True})

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from Alpaca /deviceinfo endpoint
            driver="nina_alpaca",
            capability=DeviceCapability.TELESCOPE,  # TODO: classify from Alpaca interface
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
        """Disconnect from a NINA-managed device via Alpaca.

        TODO: PUT /api/v1/{device_type}/{device_number}/connected with
        Connected=false.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting NINA device %s", device_id)
        # TODO: await self._http.put(f"/api/v1/telescope/0/connected", json={"Connected": False})
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report NINA Alpaca device health.

        TODO: GET /api/v1/{device_type}/{device_number}/connected and
        verify the connection state.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual Alpaca connected property
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="NINA device connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="NINA device disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return NINA device capabilities.

        TODO: Query Alpaca interface version and map ASCOM device types
        to DeviceCapability values.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from Alpaca device type
        return [DeviceCapability.TELESCOPE, DeviceCapability.CAMERA]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"NINA device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover NINA-managed devices via Alpaca.

        TODO: GET /api/v1/devices to enumerate all Alpaca devices.
        """
        logger.info("Discovering NINA devices at %s:%d", self._host, self._port)
        # TODO: resp = await self._http.get("/api/v1/devices")
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Telescope operations (Alpaca)
    # ------------------------------------------------------------------

    async def telescope_goto(self, device_id: str, ra: float, dec: float) -> dict[str, Any]:
        """Slew the telescope to the given RA/Dec coordinates via Alpaca.

        TODO: PUT /api/v1/telescope/{num}/slewtocoordinates with RA/Dec.
        """
        self._require_connected(device_id)
        logger.info("NINA telescope_goto %s: ra=%.4f dec=%.4f", device_id, ra, dec)
        # TODO: await self._http.put(f"/api/v1/telescope/0/slewtocoordinates", json={"RA": ra, "Dec": dec})
        return {"device_id": device_id, "action": "goto", "ra": ra, "dec": dec, "status": "slewing"}

    async def telescope_park(self, device_id: str) -> dict[str, Any]:
        """Park the telescope via Alpaca.

        TODO: PUT /api/v1/telescope/{num}/park.
        """
        self._require_connected(device_id)
        logger.info("NINA telescope_park %s", device_id)
        # TODO: await self._http.put(f"/api/v1/telescope/0/park")
        return {"device_id": device_id, "action": "park", "status": "parking"}

    # ------------------------------------------------------------------
    # Camera operations (Alpaca)
    # ------------------------------------------------------------------

    async def camera_exposure(self, device_id: str, duration: float) -> dict[str, Any]:
        """Start a camera exposure via Alpaca.

        TODO: PUT /api/v1/camera/{num}/startexposure with Duration.
        """
        self._require_connected(device_id)
        logger.info("NINA camera_exposure %s: %.1fs", device_id, duration)
        # TODO: await self._http.put(f"/api/v1/camera/0/startexposure", json={"Duration": duration})
        return {"device_id": device_id, "action": "exposure", "duration": duration, "status": "exposing"}

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