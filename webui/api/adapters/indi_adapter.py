"""INDI protocol device adapter.

Wraps the INDI XML protocol (typically via indiclient / pyindi-client) to
control telescopes, cameras, focusers, and filter wheels on a reachable INDI
server (default ``localhost:7624``).

Current status: **stub** — method bodies contain TODO markers where actual
INDI XML protocol calls belong.  This lets the router and service layer wire up
end-to-end while the INDI driver integration is still in progress.
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

# Default INDI server location (indiserver typically runs on port 7624)
_DEFAULT_INDI_HOST = "localhost"
_DEFAULT_INDI_PORT = 7624


class INDIDeviceAdapter(BaseDeviceAdapter):
    """Device adapter for the INDI (Instrument-Neutral Distributed Interface) protocol.

    Discovers devices advertised by an INDI server and exposes telescope, camera,
    focuser, and filter-wheel operations through ARES capability abstractions.

    Parameters:
        host: INDI server hostname or IP.
        port: INDI server port.
    """

    adapter_id = "indi"
    display_name = "INDI"
    kind = "indi"

    def __init__(
        self,
        host: str = _DEFAULT_INDI_HOST,
        port: int = _DEFAULT_INDI_PORT,
    ) -> None:
        self._host = host
        self._port = port
        # TODO: initialise indiclient.IPyIndiClient or equivalent
        # self._client = indiclient.IPyIndiClient(host, port)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to an INDI device by its INDI identifier.

        TODO: Open a TCP socket to the INDI server, send ``<getProperties>``
        for the target device, verify ``<defXXX>`` vectors arrive, and mark
        the device connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to INDI device %s at %s:%d", device_id, self._host, self._port)

        # TODO: Replace with actual INDI connect sequence:
        #   self._client.connect()
        #   self._client.get_properties(device_id)
        #   await confirmation / timeout

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from INDI defText "DEVICE_NAME"
            driver="indi_unknown",
            capability=DeviceCapability.TELESCOPE,  # TODO: classify from INDI interface
            adapter_kind="indi",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        # Transition to CONNECTED
        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from an INDI device.

        TODO: Send ``<newSwitchVector>`` for the CONNECTION switch set to
        ``DISCONNECT``, then tear down property subscriptions.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting INDI device %s", device_id)
        # TODO: self._client.set_switch(device_id, "CONNECTION", "DISCONNECT")
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report device health by inspecting the INDI CONNECTION property.

        TODO: Read the CONNECTION switch vector.  Return ERROR if the
        property is missing or the device is unreachable.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual CONNECTION property from INDI server
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
        """Return capabilities based on the INDI interface vector.

        TODO: Map INDI interface bits (``TELESCOPE_INTERFACE``, etc.) to
        ``DeviceCapability`` values.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from INDI INTERFACE property
        return [DeviceCapability.TELESCOPE]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current device descriptor.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"INDI device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover devices advertised by the INDI server.

        TODO: Connect to the INDI server, send ``<getProperties>``, parse
        ``<defXXXVector>`` messages, and build a ``DeviceDescriptor`` per
        device group.
        """
        logger.info("Discovering INDI devices at %s:%d", self._host, self._port)
        # TODO: self._client.connect()
        # TODO: parse defXXX vectors → DeviceDescriptor list
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Telescope operations
    # ------------------------------------------------------------------

    async def telescope_goto(self, device_id: str, ra: float, dec: float) -> dict[str, Any]:
        """Slew the telescope to the given RA/Dec coordinates.

        TODO: Send ``<newNumberVector>`` for TELESCOPE_TARGET_RA /
        TELESCOPE_TARGET_DEC, then trigger the SLEW switch.
        """
        self._require_connected(device_id)
        logger.info("Telescope GOTO %s: ra=%.4f dec=%.4f", device_id, ra, dec)
        # TODO: INDI XML protocol — set target coordinates + slew
        return {"device_id": device_id, "action": "goto", "ra": ra, "dec": dec, "status": "slewing"}

    async def telescope_sync(self, device_id: str, ra: float, dec: float) -> dict[str, Any]:
        """Sync the telescope position to the given coordinates.

        TODO: Send TELESCOPE_SYNC switch with target RA/Dec.
        """
        self._require_connected(device_id)
        logger.info("Telescope SYNC %s: ra=%.4f dec=%.4f", device_id, ra, dec)
        # TODO: INDI XML protocol — sync
        return {"device_id": device_id, "action": "sync", "ra": ra, "dec": dec, "status": "synced"}

    async def telescope_park(self, device_id: str) -> dict[str, Any]:
        """Park the telescope.

        TODO: Send TELESCOPE_PARK switch.
        """
        self._require_connected(device_id)
        logger.info("Telescope PARK %s", device_id)
        # TODO: INDI XML protocol — park
        return {"device_id": device_id, "action": "park", "status": "parking"}

    async def telescope_tracking(self, device_id: str, enabled: bool) -> dict[str, Any]:
        """Enable or disable sidereal tracking.

        TODO: Send TELESCOPE_TRACK_ON / TRACK_OFF switch.
        """
        self._require_connected(device_id)
        logger.info("Telescope TRACKING %s: %s", device_id, enabled)
        # TODO: INDI XML protocol — tracking switch
        return {"device_id": device_id, "action": "tracking", "enabled": enabled, "status": "ok"}

    # ------------------------------------------------------------------
    # Camera operations
    # ------------------------------------------------------------------

    async def camera_exposure(
        self, device_id: str, duration: float, *, frame_type: str = "Light",
    ) -> dict[str, Any]:
        """Start a camera exposure.

        TODO: Send CCD_EXPOSURE number vector with the requested duration.
        """
        self._require_connected(device_id)
        logger.info("Camera EXPOSURE %s: %.1fs (%s)", device_id, duration, frame_type)
        # TODO: INDI XML protocol — start exposure
        return {
            "device_id": device_id,
            "action": "exposure",
            "duration": duration,
            "frame_type": frame_type,
            "status": "exposing",
        }

    async def camera_abort(self, device_id: str) -> dict[str, Any]:
        """Abort the current camera exposure.

        TODO: Send CCD_ABORT_EXPOSURE switch.
        """
        self._require_connected(device_id)
        logger.info("Camera ABORT %s", device_id)
        # TODO: INDI XML protocol — abort exposure
        return {"device_id": device_id, "action": "abort", "status": "aborted"}

    async def camera_temperature(self, device_id: str) -> dict[str, Any]:
        """Read the camera sensor temperature.

        TODO: Read CCD_TEMPERATURE number vector.
        """
        self._require_connected(device_id)
        # TODO: INDI XML protocol — read temperature
        return {"device_id": device_id, "temperature_c": 0.0, "status": "stub"}

    # ------------------------------------------------------------------
    # Focuser operations
    # ------------------------------------------------------------------

    async def focuser_move(self, device_id: str, position: int) -> dict[str, Any]:
        """Move the focuser to an absolute position.

        TODO: Send FOCUSER_RELATIVE_POSITION or FOCUS_ABSOLUTE_POSITION.
        """
        self._require_connected(device_id)
        logger.info("Focuser MOVE %s → %d", device_id, position)
        # TODO: INDI XML protocol — move focuser
        return {"device_id": device_id, "action": "move", "position": position, "status": "moving"}

    async def focuser_auto_focus(self, device_id: str) -> dict[str, Any]:
        """Trigger an auto-focus run.

        TODO: Send FOCUSER_AUTOFOCUS switch or delegate to a focus-loop
        utility.
        """
        self._require_connected(device_id)
        logger.info("Focuser AUTO-FOCUS %s", device_id)
        # TODO: INDI XML protocol or focus-loop utility
        return {"device_id": device_id, "action": "auto_focus", "status": "running"}

    # ------------------------------------------------------------------
    # Filter wheel operations
    # ------------------------------------------------------------------

    async def filter_wheel_position(self, device_id: str, slot: int) -> dict[str, Any]:
        """Move the filter wheel to *slot* (0-indexed).

        TODO: Send FILTER_SLOT value and wait for confirmation.
        """
        self._require_connected(device_id)
        logger.info("Filter WHEEL %s → slot %d", device_id, slot)
        # TODO: INDI XML protocol — change filter
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