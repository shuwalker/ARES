"""NASA Worldview GIBS adapter for satellite imagery.

Connects to NASA's Global Imagery Browse Services (GIBS) API via HTTPS
to retrieve satellite imagery layers — MODIS, VIIRS, and other remote
sensing products — through the Worldview visualization interface.

Current status: **stub** — method bodies contain TODO markers where
actual GIBS REST API calls belong.
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

_DEFAULT_GIBS_URL = "https://gibs.earthdata.nasa.gov"


class WorldviewAdapter(BaseDeviceAdapter):
    """Device adapter for NASA Worldview / GIBS satellite imagery.

    Uses HTTPS to query NASA GIBS tile and image APIs, enabling ARES
    to retrieve satellite imagery for environmental monitoring, weather
    analysis, and situational awareness.

    Parameters:
        url: Base URL for GIBS API endpoints.
        api_key: Optional NASA Earthdata API key for authenticated access.
    """

    adapter_id = "worldview"
    display_name = "NASA Worldview (GIBS)"
    kind = "worldview"

    def __init__(
        self,
        url: str = _DEFAULT_GIBS_URL,
        *,
        api_key: str | None = None,
    ) -> None:
        self._url = url.rstrip("/")
        self._api_key = api_key
        # TODO: initialise httpx.AsyncClient for GIBS REST calls
        # headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        # self._http = httpx.AsyncClient(base_url=self._url, headers=headers)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to the GIBS imagery service.

        TODO: Validate API key against Earthdata, confirm endpoint
        reachability, and mark the service connected.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to NASA Worldview %s at %s", device_id, self._url)

        # TODO: Replace with actual GIBS connect:
        #   resp = await self._http.get("/api/v2/product")

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from available products
            driver="gibs",
            capability=DeviceCapability.WEATHER,  # closest match for satellite data
            adapter_kind="worldview",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the GIBS imagery service.

        TODO: Close the HTTP session and clean up cached tiles.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting Worldview device %s", device_id)
        # TODO: await self._http.aclose()
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report GIBS service health.

        TODO: HEAD the GIBS API root or a lightweight endpoint.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual service health
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="GIBS service connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="GIBS service disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return GIBS imagery capabilities.

        TODO: Query /api/v2/product for available layers and map.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from available GIBS products
        return [DeviceCapability.WEATHER]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Worldview device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available GIBS imagery products.

        TODO: GET /api/v2/product and enumerate available layers.
        """
        logger.info("Discovering GIBS products at %s", self._url)
        # TODO: resp = await self._http.get("/api/v2/product")
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # GIBS / Worldview operations
    # ------------------------------------------------------------------

    async def get_imagery(self, device_id: str, layer: str, date: str, bbox: tuple[float, float, float, float], resolution: str = "1km") -> dict[str, Any]:
        """Retrieve satellite imagery tile for the given parameters.

        TODO: Construct GIBS WMTS/WMS request URL and fetch the tile.
        """
        self._require_connected(device_id)
        logger.info("Worldview get_imagery %s: layer=%s date=%s", device_id, layer, date)
        # TODO: resp = await self._http.get(f"/wmts/epsg3857/best/{layer}/{resolution}/{...}")
        return {"device_id": device_id, "action": "get_imagery", "layer": layer, "date": date, "status": "stub"}

    async def list_layers(self, device_id: str) -> dict[str, Any]:
        """List available GIBS imagery layers.

        TODO: GET /api/v2/product and return the layer catalogue.
        """
        self._require_connected(device_id)
        logger.info("Worldview list_layers %s", device_id)
        # TODO: resp = await self._http.get("/api/v2/product")
        return {"device_id": device_id, "action": "list_layers", "layers": [], "status": "stub"}

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