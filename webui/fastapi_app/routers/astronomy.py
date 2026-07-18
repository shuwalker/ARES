"""FastAPI router for astronomical device management and night planning.

Endpoints:
    GET  /api/astronomy/connections   — discovered device list
    GET  /api/astronomy/status        — current equipment status
    POST /api/astronomy/connect/{device_id}  — connect a device
    POST /api/astronomy/disconnect/{device_id} — disconnect a device
    GET  /api/astronomy/night-info    — tonight's twilight/moon/rise-set
    GET  /api/astronomy/targets       — visible DSOs above horizon
"""

from __future__ import annotations

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from api.adapters.astronomy_service import AstronomyService
from api.adapters.base import AdapterDeviceError
from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/astronomy", tags=["astronomy"])


# ---------------------------------------------------------------------------
# Dependency: AstronomyService singleton from app state
# ---------------------------------------------------------------------------

def _get_astronomy_service(request: Any) -> AstronomyService:
    """Retrieve the ``AstronomyService`` from application state."""
    return request.app.state.astronomy_service


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/connections")
def connections(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
) -> dict[str, Any]:
    """Return all discovered devices across INDI and Alpaca adapters."""
    try:
        devices = service.device_status()
        return {"connections": devices}
    except Exception as exc:
        logger.exception("Failed to list astronomy connections")
        raise CoreApiError(500, str(exc), code="astronomy_discovery_failed") from exc


@router.get("/status")
def status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
) -> dict[str, Any]:
    """Return current equipment status for all connected devices."""
    try:
        records = service.device_status()
        return {"devices": records}
    except Exception as exc:
        logger.exception("Failed to query astronomy status")
        raise CoreApiError(500, str(exc), code="astronomy_status_failed") from exc


@router.post("/connect/{device_id}")
async def connect_device(
    device_id: str,
    *,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
    adapter_id: str = Query(default="indi", description="Adapter to use: 'indi' or 'alpaca'"),
) -> dict[str, Any]:
    """Connect to a device through the specified adapter."""
    try:
        descriptor = await service.connect_device(adapter_id, device_id)
        return descriptor.as_dict()
    except AdapterDeviceError as exc:
        raise CoreApiError(exc.status_code, exc.message, code=exc.code) from exc
    except Exception as exc:
        logger.exception("Failed to connect device %s", device_id)
        raise CoreApiError(500, str(exc), code="device_connect_failed") from exc


@router.post("/disconnect/{device_id}")
async def disconnect_device(
    device_id: str,
    *,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
    adapter_id: str = Query(default="indi", description="Adapter to use: 'indi' or 'alpaca'"),
) -> dict[str, Any]:
    """Disconnect a device through the specified adapter."""
    try:
        await service.disconnect_device(adapter_id, device_id)
        return {"device_id": device_id, "status": "disconnected"}
    except AdapterDeviceError as exc:
        raise CoreApiError(exc.status_code, exc.message, code=exc.code) from exc
    except Exception as exc:
        logger.exception("Failed to disconnect device %s", device_id)
        raise CoreApiError(500, str(exc), code="device_disconnect_failed") from exc


@router.get("/night-info")
async def night_info(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
    latitude: float = Query(default=0.0, description="Observer latitude (degrees, N positive)"),
    longitude: float = Query(default=0.0, description="Observer longitude (degrees, E positive)"),
    date: str | None = Query(default=None, description="ISO date YYYY-MM-DD, defaults to today"),
) -> dict[str, Any]:
    """Return tonight's twilight, moon, and rise-set data."""
    try:
        return await service.night_info(latitude=latitude, longitude=longitude, date=date)
    except Exception as exc:
        logger.exception("Failed to compute night info")
        raise CoreApiError(500, str(exc), code="night_info_failed") from exc


@router.get("/targets")
async def visible_targets(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AstronomyService, Depends(_get_astronomy_service)],
    latitude: float = Query(default=0.0, description="Observer latitude (degrees, N positive)"),
    longitude: float = Query(default=0.0, description="Observer longitude (degrees, E positive)"),
    date: str | None = Query(default=None, description="ISO date YYYY-MM-DD, defaults to tonight"),
    min_altitude: float = Query(default=30.0, description="Minimum altitude filter (degrees)"),
    object_types: list[str] | None = Query(default=None, description="Object type filter"),
) -> dict[str, Any]:
    """Return DSOs above the horizon for the given observer and date."""
    try:
        targets = await service.visible_targets(
            latitude=latitude,
            longitude=longitude,
            date=date,
            min_altitude=min_altitude,
            object_types=object_types,
        )
        return {"targets": targets}
    except Exception as exc:
        logger.exception("Failed to compute visible targets")
        raise CoreApiError(500, str(exc), code="targets_failed") from exc