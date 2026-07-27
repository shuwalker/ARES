"""Authenticated same-origin proxy for declared loopback extension sidecars."""

from __future__ import annotations

from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


_EXTENSION_SIDECAR_PROXY_MAX_RESPONSE_BYTES = 512 * 1024
_EXTENSION_SIDECAR_PROXY_MAX_REQUEST_BYTES = 2 * 1024 * 1024
_HOP_BY_HOP_HEADERS = {
    "connection", "keep-alive", "proxy-connection", "proxy-authenticate",
    "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade",
}


def _host_port(value: str) -> tuple[str, str | None]:
    parts = urlsplit(f"//{value}")
    try:
        port = str(parts.port) if parts.port is not None else None
    except ValueError:
        port = None
    return (parts.hostname or "").lower(), port


def _ports_match(scheme: str, left: str | None, right: str | None) -> bool:
    if left == right:
        return True
    default = "443" if scheme == "https" else "80"
    return (left or default) == (right or default)


def _extension_sidecar_proxy_redirect_url(
    allowed_origin: str,
    request_url: str,
    redirect_url: str,
) -> str | None:
    resolved = urljoin(request_url, redirect_url or "")
    allowed = urlsplit(allowed_origin or "")
    target = urlsplit(resolved)
    if not allowed.scheme or not allowed.netloc or not target.scheme or not target.netloc:
        return None
    if allowed.scheme.lower() != target.scheme.lower():
        return None
    allowed_name, allowed_port = _host_port(allowed.netloc)
    target_name, target_port = _host_port(target.netloc)
    if target_name != allowed_name or not _ports_match(allowed.scheme.lower(), target_port, allowed_port):
        return None
    return resolved


def _extension_sidecar_proxy_same_origin_opener(allowed_origin: str):
    class SameOriginRedirectHandler(HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            resolved = _extension_sidecar_proxy_redirect_url(allowed_origin, req.full_url, newurl)
            if not resolved:
                raise URLError("Extension sidecar redirect crossed declared origin")
            return super().redirect_request(req, fp, code, msg, headers, resolved)

    return build_opener(ProxyHandler({}), SameOriginRedirectHandler)


def _connection_bound_header_names(headers) -> set[str]:
    names = set(_HOP_BY_HOP_HEADERS)
    if headers:
        connection_value = next(
            (
                value
                for name, value in headers.items()
                if str(name).strip().lower() == "connection"
            ),
            "",
        )
        for token in str(connection_value or "").split(","):
            if token.strip():
                names.add(token.strip().lower())
    return names


def _forward_headers(headers) -> dict[str, str]:
    blocked = _connection_bound_header_names(headers)
    result = {}
    for name, value in headers.items():
        lower = str(name).lower()
        if (
            lower in blocked
            or lower in {"authorization", "cookie", "content-length", "host", "origin", "referer"}
            or lower.startswith("x-csrf")
        ):
            continue
        result[str(name)] = str(value)
    return result


def _response_headers(headers) -> dict[str, str]:
    blocked = _connection_bound_header_names(headers)
    result = {}
    for name, value in (headers.items() if headers else []):
        lower = str(name).lower()
        if lower in blocked or lower in {"content-length", "set-cookie"}:
            continue
        result[str(name)] = str(value)
    result["Cache-Control"] = "no-store"
    return result


def _read_extension_sidecar_proxy_body(stream) -> bytes:
    body = stream.read(_EXTENSION_SIDECAR_PROXY_MAX_RESPONSE_BYTES + 1)
    if len(body) > _EXTENSION_SIDECAR_PROXY_MAX_RESPONSE_BYTES:
        raise ValueError("Extension sidecar response too large")
    return body


def _same_origin_browser_request(request) -> bool:
    site = str(request.headers.get("sec-fetch-site") or "").strip().lower()
    origin = str(request.headers.get("origin") or "").strip()
    referer = str(request.headers.get("referer") or "").strip()
    if site == "cross-site":
        return False
    if site == "none":
        return True
    source = origin or referer
    if not source:
        return False
    parts = urlsplit(source)
    return bool(parts.scheme in {"http", "https"} and parts.netloc.lower() == str(request.headers.get("host") or "").lower())


async def proxy_extension_sidecar(request, extension_id: str, proxy_path: str):
    """Resolve, forward, and bound one extension sidecar request."""

    from fastapi.responses import JSONResponse, Response
    from api.extensions import ExtensionSidecarProxyError, resolve_extension_sidecar_proxy_target

    if not _same_origin_browser_request(request):
        return JSONResponse(
            {"error": "Cross-origin mismatch - check reverse proxy headers"},
            status_code=403,
        )
    body = await request.body() if request.method not in {"GET", "HEAD"} else None
    if body is not None and len(body) > _EXTENSION_SIDECAR_PROXY_MAX_REQUEST_BYTES:
        return JSONResponse({"error": "Extension sidecar request too large"}, status_code=413)
    try:
        target = resolve_extension_sidecar_proxy_target(
            extension_id,
            proxy_path,
            query=str(request.url.query or ""),
        )
        upstream = Request(
            target["upstream_url"],
            data=body,
            headers=_forward_headers(request.headers),
            method=request.method,
        )
        opener = _extension_sidecar_proxy_same_origin_opener(target["origin"])
        with opener.open(upstream, timeout=10) as response:
            content = _read_extension_sidecar_proxy_body(response)
            return Response(
                content=content,
                status_code=getattr(response, "status", 200),
                headers=_response_headers(response.headers),
                media_type=None,
            )
    except ExtensionSidecarProxyError as exc:
        return JSONResponse({"error": str(exc)}, status_code=exc.status)
    except HTTPError as exc:
        try:
            content = _read_extension_sidecar_proxy_body(exc)
        except ValueError as read_exc:
            return JSONResponse({"error": str(read_exc)}, status_code=502)
        return Response(
            content=content,
            status_code=exc.code,
            headers=_response_headers(exc.headers),
            media_type=None,
        )
    except ValueError as exc:
        return JSONResponse({"error": str(exc)}, status_code=502)
    except (TimeoutError, URLError, OSError):
        return JSONResponse({"error": "Failed to reach extension sidecar"}, status_code=502)


__all__ = ["proxy_extension_sidecar"]
