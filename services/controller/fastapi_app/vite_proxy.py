"""Explicit opt-in proxy for the local Vite development server."""

from __future__ import annotations

import asyncio
import http.client
import os

from fastapi import Request, Response


_HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}


def enabled() -> bool:
    return os.getenv("ARES_VITE_DEV", "").strip().lower() in {"1", "true", "yes", "on"}


def _fetch(method: str, target: str, accept: str) -> tuple[int, list[tuple[str, str]], bytes] | None:
    port = int(os.getenv("ARES_VITE_PORT", "5173"))
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.request(method, target, headers={"Accept": accept, "Host": f"127.0.0.1:{port}"})
        response = connection.getresponse()
        return response.status, response.getheaders(), response.read()
    except (ConnectionError, OSError, TimeoutError, http.client.HTTPException):
        return None
    finally:
        connection.close()


async def proxy_vite_request(request: Request) -> Response | None:
    if not enabled():
        return None
    target = request.url.path
    if request.url.query:
        target += "?" + request.url.query
    fetched = await asyncio.to_thread(
        _fetch,
        request.method,
        target,
        request.headers.get("accept", "*/*"),
    )
    if fetched is None:
        return None
    status, raw_headers, body = fetched
    headers = {
        name: value
        for name, value in raw_headers
        if name.lower() not in _HOP_BY_HOP | {"content-length", "server"}
    }
    headers["X-ARES-Frontend"] = "vite-dev"
    return Response(body, status_code=status, headers=headers)


__all__ = ["enabled", "proxy_vite_request"]
