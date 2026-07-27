"""Transport-neutral browser origin and CORS policy."""

from __future__ import annotations

import os
import sys
from urllib.parse import urlsplit


def normalize_host_port(value: str) -> tuple[str, str | None]:
    value = str(value or "").strip().lower()
    if not value:
        return "", None
    if value.startswith("["):
        end = value.find("]")
        if end >= 0:
            host, rest = value[1:end], value[end + 1 :]
            return (host, rest[1:]) if rest.startswith(":") and rest[1:].isdigit() else (host, None)
    if value.count(":") == 1:
        host, port = value.rsplit(":", 1)
        if port.isdigit():
            return host, port
    return value, None


def ports_match(scheme: str, origin_port: str | None, allowed_port: str | None) -> bool:
    if origin_port == allowed_port:
        return True
    default = "443" if scheme == "https" else "80"
    return (not origin_port and allowed_port == default) or (not allowed_port and origin_port == default)


def allowed_public_origins() -> set[str]:
    result = set()
    for raw in os.getenv("ARES_WEBUI_ALLOWED_ORIGINS", "").split(","):
        value = raw.strip().rstrip("/").lower()
        if not value:
            continue
        if not value.startswith(("http://", "https://")):
            print(
                f"[webui] WARNING: ARES_WEBUI_ALLOWED_ORIGINS entry {value!r} is missing the scheme. Entry ignored.",
                file=sys.stderr,
                flush=True,
            )
            continue
        result.add(value)
    return result


def _header(headers, name: str) -> str:
    value = headers.get(name)
    if value is None:
        value = headers.get(name.title())
    if value is None and hasattr(headers, "items"):
        value = next((item for key, item in headers.items() if str(key).lower() == name.lower()), None)
    return str(value or "")


def browser_origin_allowed(headers, *, require_provenance: bool = False) -> bool:
    origin = _header(headers, "origin").strip()
    referer = _header(headers, "referer").strip()
    fetch_site = _header(headers, "sec-fetch-site").strip().lower()
    if not (origin or referer or fetch_site):
        return not require_provenance
    if fetch_site == "cross-site":
        return False
    target = origin or referer
    if not target:
        return fetch_site == "none" or (fetch_site == "same-origin" and not require_provenance)
    try:
        parsed = urlsplit(target)
        scheme = parsed.scheme.lower()
        origin_name = (parsed.hostname or "").lower()
        origin_port = str(parsed.port) if parsed.port is not None else None
        origin_value = f"{scheme}://{parsed.netloc}".rstrip("/").lower()
    except ValueError:
        return False
    if scheme not in {"http", "https"} or not origin_name:
        return False
    if origin_value in allowed_public_origins():
        return True
    allowed_hosts = [_header(headers, "host").strip()]
    if os.getenv("ARES_WEBUI_TRUST_FORWARDED_HOST", "").strip().lower() in {"1", "true", "yes", "on"}:
        allowed_hosts.extend(
            _header(headers, name).strip()
            for name in ("x-forwarded-host", "x-real-host")
        )
    for allowed in allowed_hosts:
        allowed_name, allowed_port = normalize_host_port(allowed)
        if origin_name == allowed_name and ports_match(scheme, origin_port, allowed_port):
            return True
    return False


_normalize_host_port = normalize_host_port
_ports_match = ports_match
_allowed_public_origins = allowed_public_origins


__all__ = [
    "allowed_public_origins",
    "browser_origin_allowed",
    "normalize_host_port",
    "ports_match",
]
