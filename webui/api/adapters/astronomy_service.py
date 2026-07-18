"""High-level astronomy service aggregating devices, night planning, and session management.

The ``AstronomyService`` sits between the FastAPI router and the device adapters.
It owns the adapter instances, coordinates discovery, and provides night-planning
utilities (twilight times, moon data, rise/set tables, target visibility).

Night data is sourced from ARESCore's ``NighttimeCalculator`` via the internal
API, falling back to a local calculation when the core is unavailable.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from .base import (
    AdapterDeviceError,
    BaseDeviceAdapter,
    DeviceCapability,
    DeviceConnectionState,
    DeviceDescriptor,
    DeviceHealth,
)
from .discovery import DeviceDiscoveryService
from .indi_adapter import INDIDeviceAdapter
from .alpaca_adapter import AlpacaDeviceAdapter

logger = logging.getLogger(__name__)


class AstronomyService:
    """Aggregate service for astronomical device management and night planning.

    Parameters:
        indi_host: INDI server hostname.
        indi_port: INDI server port.
        alpaca_host: Alpaca server hostname.
        alpaca_port: Alpaca server port.
    """

    def __init__(
        self,
        *,
        indi_host: str = "localhost",
        indi_port: int = 7624,
        alpaca_host: str = "localhost",
        alpaca_port: int = 11111,
    ) -> None:
        self._indi = INDIDeviceAdapter(host=indi_host, port=indi_port)
        self._alpaca = AlpacaDeviceAdapter(host=alpaca_host, port=alpaca_port)
        self._discovery = DeviceDiscoveryService(
            indi_host=indi_host,
            indi_port=indi_port,
            alpaca_host=alpaca_host,
            alpaca_port=alpaca_port,
        )
        self._adapters: dict[str, BaseDeviceAdapter] = {
            self._indi.adapter_id: self._indi,
            self._alpaca.adapter_id: self._alpaca,
        }

    # ------------------------------------------------------------------
    # Device aggregation
    # ------------------------------------------------------------------

    @property
    def adapters(self) -> dict[str, BaseDeviceAdapter]:
        """All registered device adapters keyed by ``adapter_id``."""
        return dict(self._adapters)

    def adapter(self, adapter_id: str) -> BaseDeviceAdapter:
        """Retrieve a device adapter by ID.

        Raises:
            AdapterDeviceError: If the adapter is unknown.
        """
        adapter = self._adapters.get(adapter_id)
        if adapter is None:
            raise AdapterDeviceError(
                404,
                f"Unknown device adapter: {adapter_id}",
                code="unknown_adapter",
            )
        return adapter

    async def discover_all_devices(self) -> list[DeviceDescriptor]:
        """Discover devices across all adapters."""
        all_devices: list[DeviceDescriptor] = []
        for adapter in self._adapters.values():
            try:
                all_devices.extend(await adapter.discover())
            except Exception:
                logger.warning("Discovery failed for adapter %s", adapter.adapter_id, exc_info=True)
        return all_devices

    async def connect_device(self, adapter_id: str, device_id: str) -> DeviceDescriptor:
        """Connect a device through the specified adapter.

        Raises:
            AdapterDeviceError: If the adapter or device is unavailable.
        """
        adapter = self.adapter(adapter_id)
        return await adapter.connect(device_id)

    async def disconnect_device(self, adapter_id: str, device_id: str) -> None:
        """Disconnect a device through the specified adapter.

        Raises:
            AdapterDeviceError: If the adapter is unknown.
        """
        adapter = self.adapter(adapter_id)
        await adapter.disconnect(device_id)

    def device_status(self) -> list[dict[str, Any]]:
        """Return connection records for all known devices across all adapters."""
        records: list[dict[str, Any]] = []
        for adapter in self._adapters.values():
            try:
                records.extend(adapter.all_connection_records())
            except Exception:
                logger.warning(
                    "Status query failed for adapter %s", adapter.adapter_id, exc_info=True,
                )
        return records

    # ------------------------------------------------------------------
    # Night planning
    # ------------------------------------------------------------------

    async def night_info(self, *, latitude: float, longitude: float, date: str | None = None) -> dict[str, Any]:
        """Compute tonight's twilight, moon, and rise-set data.

        Uses ARESCore's NighttimeCalculator when available; falls back to a
        local simplified calculation.

        Args:
            latitude: Observer latitude (degrees, North positive).
            longitude: Observer longitude (degrees, East positive).
            date: ISO date string ``YYYY-MM-DD``; defaults to today.

        Returns:
            A dict with twilight times, moon phase, and rise/set pairs.
        """
        # TODO: Call ARESCore API for NighttimeCalculator data
        #   response = await self._core_client.get(f"/api/night/info?lat={lat}&lon={lon}&date={date}")
        logger.info("Computing night info for lat=%.4f lon=%.4f date=%s", latitude, longitude, date)

        # Stub: simplified local calculation
        obs_date = date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return {
            "date": obs_date,
            "latitude": latitude,
            "longitude": longitude,
            "twilight": {
                "astronomical_dawn": None,   # TODO: compute
                "nautical_dawn": None,        # TODO: compute
                "civil_dawn": None,            # TODO: compute
                "civil_dusk": None,            # TODO: compute
                "nautical_dusk": None,          # TODO: compute
                "astronomical_dusk": None,      # TODO: compute
            },
            "moon": {
                "phase": None,          # TODO: compute
                "illumination": None,   # TODO: compute
                "rise": None,           # TODO: compute
                "set": None,           # TODO: compute
            },
            "status": "stub",
        }

    async def visible_targets(
        self,
        *,
        latitude: float,
        longitude: float,
        date: str | None = None,
        min_altitude: float = 30.0,
        object_types: list[str] | None = None,
    ) -> list[dict[str, Any]]:
        """Return DSOs above the horizon for the given observer and date.

        Args:
            latitude: Observer latitude (degrees, North positive).
            longitude: Observer longitude (degrees, East positive).
            date: ISO date string ``YYYY-MM-DD``; defaults to tonight.
            min_altitude: Minimum altitude filter in degrees.
            object_types: Filter by object type (e.g. ``["galaxy", "nebula"]``).

        Returns:
            A list of target dicts with name, type, RA, Dec, altitude, and
            best-viewing time.
        """
        # TODO: Integrate with ARESCore catalog + ephemeris engine
        logger.info("Computing visible targets for lat=%.4f lon=%.4f date=%s", latitude, longitude, date)
        return []

    # ------------------------------------------------------------------
    # Imaging session management (stubs)
    # ------------------------------------------------------------------

    async def start_imaging_session(
        self,
        *,
        adapter_id: str,
        device_id: str,
        target: str,
        exposure: float,
        count: int = 1,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Start an imaging session on a connected camera device.

        TODO: Orchestrate target acquisition (slew, center, focus), then
        iterate exposure sequence.
        """
        adapter = self.adapter(adapter_id)
        if DeviceCapability.CAMERA not in adapter.capabilities(device_id):
            raise AdapterDeviceError(
                400,
                f"Device {device_id} does not support camera operations",
                code="unsupported_capability",
            )
        return {
            "session_id": "stub",
            "device_id": device_id,
            "target": target,
            "exposure": exposure,
            "count": count,
            "status": "stub",
        }