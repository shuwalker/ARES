"""Open-WebUI REST adapter for alternative WebUI control.

Connects to an Open-WebUI instance via its REST API to provide an
alternative chat-based interface for ARES.  Open-WebUI exposes
endpoints for conversations, model management, file uploads, and
user administration that this adapter wraps behind the ARES device
abstraction.

Current status: **stub** — method bodies contain TODO markers where
actual HTTP REST calls belong.
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

_DEFAULT_OPENWEBUI_URL = "http://localhost:3000"


class OpenWebUIAdapter(BaseDeviceAdapter):
    """Device adapter for Open-WebUI REST API.

    Uses httpx (or equivalent async HTTP client) to communicate with an
    Open-WebUI server, exposing chat, model, and file operations through
    the ARES adapter interface.

    Parameters:
        url: Base URL of the Open-WebUI instance.
        api_key: Optional API key for authentication.
    """

    adapter_id = "openwebui"
    display_name = "Open-WebUI"
    kind = "openwebui"

    def __init__(
        self,
        url: str = _DEFAULT_OPENWEBUI_URL,
        *,
        api_key: str | None = None,
    ) -> None:
        self._url = url.rstrip("/")
        self._api_key = api_key
        # TODO: initialise httpx.AsyncClient with auth headers
        # headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        # self._http = httpx.AsyncClient(base_url=self._url, headers=headers)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to an Open-WebUI instance.

        TODO: Validate API key, fetch user info, and mark the session
        connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to Open-WebUI %s at %s", device_id, self._url)

        # TODO: Replace with actual REST connect:
        #   resp = await self._http.get("/api/v1/auths/me")
        #   user = resp.json()

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from /api/v1/auths/me
            driver="openwebui",
            capability=DeviceCapability.SWITCH,
            adapter_kind="openwebui",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the Open-WebUI instance.

        TODO: Close the HTTP session and clean up state.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Open-WebUI device %s", device_id)
        # TODO: await self._http.aclose()
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report Open-WebUI instance health.

        TODO: GET /api/v1/health or equivalent.
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
                message="Open-WebUI connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Open-WebUI disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return Open-WebUI capabilities.

        TODO: Query /api/v1/configs or derive from available endpoints.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from server feature flags
        return [DeviceCapability.SWITCH]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Open-WebUI device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available Open-WebUI instances.

        TODO: Query the configured Open-WebUI URL for session info.
        """
        logger.info("Discovering Open-WebUI instances at %s", self._url)
        # TODO: resp = await self._http.get("/api/v1/configs")
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Open-WebUI operations
    # ------------------------------------------------------------------

    async def list_models(self, device_id: str) -> dict[str, Any]:
        """List available LLM models on the Open-WebUI instance.

        TODO: GET /api/v1/models and return the list.
        """
        self._require_connected(device_id)
        logger.info("Open-WebUI list_models %s", device_id)
        # TODO: resp = await self._http.get("/api/v1/models")
        # return resp.json()
        return {"device_id": device_id, "action": "list_models", "models": [], "status": "stub"}

    async def create_chat(self, device_id: str, model: str, message: str) -> dict[str, Any]:
        """Create a new chat conversation on Open-WebUI.

        TODO: POST /api/v1/chats with model and message payload.
        """
        self._require_connected(device_id)
        logger.info("Open-WebUI create_chat %s: model=%s", device_id, model)
        # TODO: resp = await self._http.post("/api/v1/chats", json={...})
        return {"device_id": device_id, "action": "create_chat", "model": model, "status": "created"}

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