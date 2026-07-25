"""ASGI error boundaries do not attempt a second legacy socket write."""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _broken_app(exception):
    router = APIRouter()

    @router.get("/api/test/disconnect")
    def fail():
        raise exception

    return create_app(install_api_routes=lambda app: app.include_router(router))


def test_real_application_error_becomes_one_500_response():
    with TestClient(_broken_app(ValueError("real bug")), raise_server_exceptions=False) as client:
        response = client.get("/api/test/disconnect")
    assert response.status_code == 500
    assert response.content == b"Internal Server Error"


def test_disconnect_class_does_not_trigger_legacy_json_retry():
    with TestClient(_broken_app(BrokenPipeError()), raise_server_exceptions=False) as client:
        response = client.get("/api/test/disconnect")
    assert response.status_code == 500
    # Starlette owns the single ASGI error response. ARES no longer catches a
    # failed socket write and tries to serialize a second response to it.
    assert response.content == b"Internal Server Error"


def test_uvicorn_transport_is_bounded_for_slow_or_dropped_clients():
    from bootstrap import build_uvicorn_argv

    argv = build_uvicorn_argv("python", "127.0.0.1", 8787)
    assert "--limit-concurrency" in argv
    assert "--timeout-keep-alive" in argv
