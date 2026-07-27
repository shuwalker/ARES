"""Long-lived FastAPI SSE responses must not force connection closure."""

from __future__ import annotations

from fastapi.responses import StreamingResponse

from fastapi_app.routers.realtime import _sse_response


async def _empty_stream():
    if False:
        yield b""


def test_sse_response_does_not_emit_connection_close():
    response = _sse_response(_empty_stream())
    assert isinstance(response, StreamingResponse)
    assert response.media_type == "text/event-stream"
    assert response.headers.get("connection") is None


def test_sse_response_disables_proxy_buffering_and_cache():
    response = _sse_response(_empty_stream())
    assert response.headers["x-accel-buffering"] == "no"
    assert response.headers["cache-control"] == "no-cache"
