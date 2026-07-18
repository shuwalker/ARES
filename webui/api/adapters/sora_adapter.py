"""Open-Sora video generation adapter.

Connects to an Open-Sora video generation API server (FastAPI or
compatible) to submit text-to-video and image-to-video generation
requests, poll job status, and retrieve completed video outputs.

Current status: **stub** — method bodies contain TODO markers where
actual API calls belong.
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

_DEFAULT_SORA_URL = "http://localhost:8000"


class SoraAdapter(BaseDeviceAdapter):
    """Device adapter for Open-Sora video generation API.

    Uses async HTTP to communicate with an Open-Sora server instance,
    exposing video generation, status polling, and retrieval through
    the ARES adapter interface.

    Parameters:
        url: Base URL of the Open-Sora API server.
        api_key: Optional API key for authenticated access.
    """

    adapter_id = "sora"
    display_name = "Open-Sora"
    kind = "sora"

    def __init__(
        self,
        url: str = _DEFAULT_SORA_URL,
        *,
        api_key: str | None = None,
    ) -> None:
        self._url = url.rstrip("/")
        self._api_key = api_key
        # TODO: initialise httpx.AsyncClient for REST calls
        # headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        # self._http = httpx.AsyncClient(base_url=self._url, headers=headers)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to the Open-Sora API server.

        TODO: Verify the server is reachable and API key is valid.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to Open-Sora %s at %s", device_id, self._url)

        # TODO: Replace with actual connect:
        #   resp = await self._http.get("/api/v1/health")

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from server info
            driver="open_sora",
            capability=DeviceCapability.CAMERA,  # closest match for video output
            adapter_kind="sora",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the Open-Sora API server.

        TODO: Cancel any pending generation jobs and close the HTTP session.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Sora device %s", device_id)
        # TODO: await self._http.aclose()
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report Open-Sora server health.

        TODO: GET /api/v1/health and parse the response.
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
                message="Open-Sora connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Open-Sora disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return Open-Sora generation capabilities.

        TODO: Query server for supported generation modes and map.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from server configuration
        return [DeviceCapability.CAMERA]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Sora device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available Open-Sora server endpoints.

        TODO: Query the server for GPU/model configuration.
        """
        logger.info("Discovering Open-Sora endpoints at %s", self._url)
        # TODO: resp = await self._http.get("/api/v1/config")
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Video generation operations
    # ------------------------------------------------------------------

    async def generate_video(self, device_id: str, prompt: str, *, duration: float = 4.0, resolution: str = "480p") -> dict[str, Any]:
        """Submit a text-to-video generation request.

        TODO: POST /api/v1/generate with the prompt and parameters,
        returning a job ID for status polling.
        """
        self._require_connected(device_id)
        logger.info("Sora generate_video %s: prompt=%s", device_id, prompt[:80])
        # TODO: resp = await self._http.post("/api/v1/generate", json={...})
        return {"device_id": device_id, "action": "generate_video", "job_id": "stub-job-id", "status": "queued"}

    async def get_job_status(self, device_id: str, job_id: str) -> dict[str, Any]:
        """Poll the status of a video generation job.

        TODO: GET /api/v1/status/{job_id} and return progress/state.
        """
        self._require_connected(device_id)
        logger.info("Sora get_job_status %s: job_id=%s", device_id, job_id)
        # TODO: resp = await self._http.get(f"/api/v1/status/{job_id}")
        return {"device_id": device_id, "action": "get_job_status", "job_id": job_id, "status": "processing", "progress": 0.0}

    async def get_video(self, device_id: str, job_id: str) -> dict[str, Any]:
        """Retrieve a completed video output.

        TODO: GET /api/v1/video/{job_id} and return the download URL or
        binary data.
        """
        self._require_connected(device_id)
        logger.info("Sora get_video %s: job_id=%s", device_id, job_id)
        # TODO: resp = await self._http.get(f"/api/v1/video/{job_id}")
        return {"device_id": device_id, "action": "get_video", "job_id": job_id, "url": "", "status": "stub"}

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