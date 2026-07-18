"""Minecraft embodiment adapter via HermesCraft CLI.

Connects to a running Minecraft server instance through the
hermescraft/HermesCraft ``mc`` CLI, which provides a programmatic
bridge for ARES to interact with the Minecraft world — placing blocks,
moving the player entity, reading terrain, and executing commands.

Current status: **stub** — method bodies contain TODO markers where
actual CLI invocations belong.
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

_DEFAULT_MC_HOST = "localhost"
_DEFAULT_MC_PORT = 25565


class MinecraftAdapter(BaseDeviceAdapter):
    """Device adapter for Minecraft embodiment via HermesCraft CLI.

    Uses the ``mc`` CLI (or direct RCON connection) to control a
    Minecraft server, enabling ARES to act as an embodied agent inside
    the game world.

    Parameters:
        host: Minecraft server hostname.
        port: Minecraft server port (or RCON port).
    """

    adapter_id = "minecraft"
    display_name = "Minecraft (HermesCraft)"
    kind = "minecraft"

    def __init__(
        self,
        host: str = _DEFAULT_MC_HOST,
        port: int = _DEFAULT_MC_PORT,
    ) -> None:
        self._host = host
        self._port = port
        # TODO: initialise mc CLI subprocess or RCON client
        # from mc import Client
        # self._client = Client(host, port)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to a Minecraft server via HermesCraft CLI.

        TODO: Launch or attach to the mc CLI, authenticate with the
        server, and mark the player connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to Minecraft %s at %s:%d", device_id, self._host, self._port)

        # TODO: Replace with actual CLI connect:
        #   await self._client.connect(device_id)

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from server player list
            driver="hermescraft",
            capability=DeviceCapability.SWITCH,  # TODO: define EMBODIMENT capability
            adapter_kind="minecraft",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the Minecraft server.

        TODO: Send disconnect command via CLI and clean up.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Minecraft device %s", device_id)
        # TODO: await self._client.disconnect(device_id)
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report Minecraft server health.

        TODO: Ping the server list ping or run ``mc health``.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual server ping response
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="Minecraft server connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Minecraft server disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return Minecraft embodiment capabilities.

        TODO: Query server for available command set and map.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from server feature set
        return [DeviceCapability.SWITCH]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Minecraft device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available Minecraft server instances.

        TODO: Scan LAN or query configured server list via mc CLI.
        """
        logger.info("Discovering Minecraft servers at %s:%d", self._host, self._port)
        # TODO: await self._client.list_servers()
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Minecraft operations
    # ------------------------------------------------------------------

    async def execute_command(self, device_id: str, command: str) -> dict[str, Any]:
        """Execute a Minecraft server command.

        TODO: Run ``mc execute <command>`` or send via RCON.
        """
        self._require_connected(device_id)
        logger.info("Minecraft execute_command %s: %s", device_id, command)
        # TODO: result = await self._client.execute(command)
        return {"device_id": device_id, "action": "execute_command", "command": command, "status": "executed"}

    async def get_player_position(self, device_id: str) -> dict[str, Any]:
        """Get the current player position in the Minecraft world.

        TODO: Run ``mc player pos`` and parse the response.
        """
        self._require_connected(device_id)
        logger.info("Minecraft get_player_position %s", device_id)
        # TODO: pos = await self._client.player_position()
        return {"device_id": device_id, "action": "get_player_position", "x": 0, "y": 64, "z": 0, "status": "stub"}

    async def place_block(self, device_id: str, x: int, y: int, z: int, block_type: str) -> dict[str, Any]:
        """Place a block at the specified world coordinates.

        TODO: Run ``mc setblock <x> <y> <z> <block_type>``.
        """
        self._require_connected(device_id)
        logger.info("Minecraft place_block %s: (%d,%d,%d) %s", device_id, x, y, z, block_type)
        # TODO: await self._client.set_block(x, y, z, block_type)
        return {"device_id": device_id, "action": "place_block", "x": x, "y": y, "z": z, "block_type": block_type, "status": "placed"}

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