"""Open-LLM-VTuber adapter for Live2D avatar control.

Connects to an Open-LLM-VTuber instance via its FastAPI REST and
WebSocket endpoints to drive a Live2D avatar with LLM-generated speech
and expressions.  The VTuber server exposes audio streaming, emotion
tags, and motion commands over WebSocket while configuration and chat
history are managed through REST.

Current status: **stub** — method bodies contain TODO markers where
actual HTTP/WS protocol calls belong.
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

_DEFAULT_VTUBER_HOST = "localhost"
_DEFAULT_VTUBER_PORT = 8000


class VTuberAdapter(BaseDeviceAdapter):
    """Device adapter for Open-LLM-VTuber Live2D avatar control.

    Opens a WebSocket to the VTuber server for real-time audio and
    expression streaming, and uses REST for configuration and chat.

    Parameters:
        host: Open-LLM-VTuber server hostname.
        port: Open-LLM-VTuber server port.
    """

    adapter_id = "vtuber"
    display_name = "Open-LLM-VTuber"
    kind = "vtuber"

    def __init__(
        self,
        host: str = _DEFAULT_VTUBER_HOST,
        port: int = _DEFAULT_VTUBER_PORT,
    ) -> None:
        self._host = host
        self._port = port
        # TODO: initialise httpx.AsyncClient for REST + websockets client
        # self._http = httpx.AsyncClient(base_url=f"http://{host}:{port}")
        # self._ws = None
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to an Open-LLM-VTuber avatar endpoint.

        TODO: Open REST session and WebSocket to the VTuber server,
        perform authentication, and mark the avatar connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to VTuber %s at %s:%d", device_id, self._host, self._port)

        # TODO: Replace with actual connect sequence:
        #   resp = await self._http.post("/api/session", json={"avatar": device_id})
        #   self._ws = await websockets.connect(f"ws://{self._host}:{self._port}/ws")

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from VTuber config
            driver="vtuber",
            capability=DeviceCapability.SWITCH,  # TODO: define AVATAR capability
            adapter_kind="vtuber",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the VTuber avatar.

        TODO: Close WebSocket and REST session gracefully.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting VTuber device %s", device_id)
        # TODO: await self._ws.close()
        # TODO: await self._http.aclose()
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report VTuber server health.

        TODO: GET /api/health on the VTuber server.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual health endpoint
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="VTuber connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="VTuber disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return VTuber avatar capabilities.

        TODO: Query /api/capabilities for supported modalities.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from server response
        return [DeviceCapability.SWITCH]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"VTuber device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available VTuber avatar profiles.

        TODO: GET /api/avatars from the VTuber server.
        """
        logger.info("Discovering VTuber avatars at %s:%d", self._host, self._port)
        # TODO: resp = await self._http.get("/api/avatars")
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # VTuber operations
    # ------------------------------------------------------------------

    async def send_chat(self, device_id: str, message: str) -> dict[str, Any]:
        """Send a chat message to the VTuber LLM for response + animation.

        TODO: POST /api/chat with the message, receive audio + expression data.
        """
        self._require_connected(device_id)
        logger.info("VTuber send_chat %s: %s", device_id, message[:80])
        # TODO: resp = await self._http.post("/api/chat", json={"text": message, "avatar": device_id})
        return {"device_id": device_id, "action": "send_chat", "status": "responding"}

    async def set_emotion(self, device_id: str, emotion: str) -> dict[str, Any]:
        """Set the Live2D avatar emotion/expression.

        TODO: Send emotion tag over WebSocket.
        """
        self._require_connected(device_id)
        logger.info("VTuber set_emotion %s: %s", device_id, emotion)
        # TODO: await self._ws.send(json.dumps({"type": "emotion", "name": emotion}))
        return {"device_id": device_id, "action": "set_emotion", "emotion": emotion, "status": "applied"}

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