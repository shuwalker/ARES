"""Bambu Lab / OrcaSlicer MQTT adapter for 3D printer control.

Connects to a Bambu Lab 3D printer (or OrcaSlicer MQTT bridge) via
the MQTT protocol to monitor print status, submit print jobs, and
control printer hardware.  Bambu Lab printers expose an MQTT broker
with topics for status reporting and command dispatch; OrcaSlicer can
also bridge these topics.

Current status: **stub** — method bodies contain TODO markers where
actual MQTT publish/subscribe calls belong.
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

_DEFAULT_MQTT_HOST = "localhost"
_DEFAULT_MQTT_PORT = 8883  # Bambu Lab default MQTT over TLS


class BambuAdapter(BaseDeviceAdapter):
    """Device adapter for Bambu Lab / OrcaSlicer 3D printers via MQTT.

    Subscribes to printer status topics and publishes commands to
    control print jobs, temperatures, and movement.

    Parameters:
        host: MQTT broker hostname (printer IP or OrcaSlicer bridge).
        port: MQTT broker port (8883 for Bambu Lab TLS).
        serial: Printer serial number used as MQTT topic prefix.
    """

    adapter_id = "bambu"
    display_name = "Bambu Lab / OrcaSlicer"
    kind = "bambu"

    def __init__(
        self,
        host: str = _DEFAULT_MQTT_HOST,
        port: int = _DEFAULT_MQTT_PORT,
        *,
        serial: str = "",
    ) -> None:
        self._host = host
        self._port = port
        self._serial = serial
        # TODO: initialise aiomqtt.Client
        # import aiomqtt
        # self._mqtt = aiomqtt.Client(hostname=host, port=port)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to the Bambu Lab printer MQTT broker.

        TODO: Open MQTT connection, authenticate with printer credentials,
        subscribe to status topics, and mark connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to Bambu printer %s at %s:%d", device_id, self._host, self._port)

        # TODO: Replace with actual MQTT connect:
        #   await self._mqtt.connect()
        #   await self._mqtt.subscribe(f"device/{self._serial}/report/#")

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from MQTT status message
            driver="bambu_mqtt",
            capability=DeviceCapability.SWITCH,  # TODO: define PRINTER capability
            adapter_kind="bambu",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the Bambu Lab MQTT broker.

        TODO: Unsubscribe from topics and close the MQTT connection.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Bambu device %s", device_id)
        # TODO: await self._mqtt.disconnect()
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report Bambu Lab printer health.

        TODO: Check MQTT connection state and last received status message.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual printer status from last MQTT message
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="Bambu printer connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Bambu printer disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return Bambu Lab printer capabilities.

        TODO: Derive from printer model reported in MQTT status.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from printer model capabilities
        return [DeviceCapability.SWITCH]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Bambu device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available Bambu Lab printers.

        TODO: Probe for printers on the local network or query OrcaSlicer.
        """
        logger.info("Discovering Bambu printers at %s:%d", self._host, self._port)
        # TODO: network discovery or OrcaSlicer device list
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Printer operations
    # ------------------------------------------------------------------

    async def start_print(self, device_id: str, gcode_file: str) -> dict[str, Any]:
        """Submit a print job to the Bambu Lab printer.

        TODO: Publish print command to the MQTT topic
        ``device/{serial}/command``.
        """
        self._require_connected(device_id)
        logger.info("Bambu start_print %s: %s", device_id, gcode_file)
        # TODO: await self._mqtt.publish(f"device/{self._serial}/command", payload=...)
        return {"device_id": device_id, "action": "start_print", "gcode_file": gcode_file, "status": "printing"}

    async def get_print_status(self, device_id: str) -> dict[str, Any]:
        """Get current print status from the printer.

        TODO: Read the last status message from the MQTT report topic.
        """
        self._require_connected(device_id)
        logger.info("Bambu get_print_status %s", device_id)
        # TODO: read from cached MQTT status message
        return {"device_id": device_id, "action": "get_print_status", "status": "idle", "progress": 0.0}

    async def cancel_print(self, device_id: str) -> dict[str, Any]:
        """Cancel the current print job.

        TODO: Publish cancel command to the MQTT command topic.
        """
        self._require_connected(device_id)
        logger.info("Bambu cancel_print %s", device_id)
        # TODO: await self._mqtt.publish(f"device/{self._serial}/command", payload="cancel")
        return {"device_id": device_id, "action": "cancel_print", "status": "cancelled"}

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