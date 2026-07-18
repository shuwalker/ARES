"""Production FastAPI application factory for ARES.

Run the scaffold directly with::

    uvicorn fastapi_app.main:app --host 127.0.0.1 --port 8787
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
import time

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .adapters import AdapterRegistry
from .errors import CoreApiError
from .frontend import CsrfTokenResolver, create_frontend_router
from .lifecycle import ares_lifespan
from .routers import install_core_routers
from .realtime import RealtimeService
from .security import security_headers_middleware
from .services import AresCoreService


ApiInstaller = Callable[[FastAPI], None]


async def request_diagnostics_middleware(request: Request, call_next):
    """Retain bounded slow-request diagnostics at the ASGI boundary."""

    from api.request_diagnostics import RequestDiagnostics

    # Uvicorn owns the accept loop, so expose an application-level request
    # heartbeat with the same watchdog contract as the former HTTP server.
    state = request.app.state
    state.requests_total = int(getattr(state, "requests_total", 0)) + 1
    state.last_request_at = time.time()
    diagnostics = RequestDiagnostics.maybe_start(
        request.method,
        request.url.path,
    )
    if diagnostics is not None:
        diagnostics.stage("fastapi_dispatch")
    try:
        return await call_next(request)
    finally:
        if diagnostics is not None:
            diagnostics.finish()


def create_app(
    *,
    frontend_root: Path | None = None,
    csrf_resolver: CsrfTokenResolver | None = None,
    install_api_routes: ApiInstaller | None = None,
    core_service: AresCoreService | None = None,
    realtime_service: RealtimeService | None = None,
    adapter_registry: AdapterRegistry | None = None,
    enable_lifecycle: bool = False,
) -> FastAPI:
    """Build the application, optionally without background services for tests.

    ``install_api_routes`` remains an explicit test/migration seam for later
    route families; core routers are always installed before the catch-all.
    """
    application = FastAPI(
        title="ARES WebUI",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=ares_lifespan if enable_lifecycle else None,
    )
    application.state.core_service = core_service or AresCoreService()
    application.state.requests_total = 0
    application.state.last_request_at = 0.0
    registry = (
        adapter_registry
        or getattr(realtime_service, "adapters", None)
        or AdapterRegistry()
    )
    application.state.adapter_registry = registry
    application.state.realtime_service = realtime_service or RealtimeService(
        adapter_registry=registry
    )
    application.middleware("http")(request_diagnostics_middleware)
    application.middleware("http")(security_headers_middleware)

    @application.exception_handler(CoreApiError)
    async def core_api_error_handler(_request: Request, exc: CoreApiError):
        return JSONResponse(exc.payload(), status_code=exc.status_code)

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        # Preserve the established ARES REST contract. Browser and automation
        # clients historically treat malformed /api input as Bad Request;
        # Pydantic still supplies the structured validation details.
        status_code = 400 if request.url.path.startswith("/api/") else 422
        return JSONResponse(
            jsonable_encoder(
                {"error": "Invalid request", "details": exc.errors()},
                custom_encoder={Exception: str},
            ),
            status_code=status_code,
        )

    install_core_routers(application)

    if install_api_routes is not None:
        install_api_routes(application)

    # Keep this last. Route order is part of the API-not-swallowed invariant.
    application.include_router(
        create_frontend_router(
            frontend_root=frontend_root,
            csrf_resolver=csrf_resolver,
        )
    )
    return application


app = create_app(enable_lifecycle=True)
