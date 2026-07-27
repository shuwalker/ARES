"""Socket-peer and reverse-proxy trust decisions shared by HTTP transports."""

from __future__ import annotations

import ipaddress
import os
from typing import Any


def truthy_env(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in {"1", "true", "yes", "on"}


def request_client_ip(connection: Any) -> str:
    address = getattr(connection, "client_address", None)
    if address:
        return str(address[0] or "")
    client = getattr(connection, "client", None)
    return str(getattr(client, "host", "") or "")


def ip_is_loopback_or_private(raw: str) -> tuple[bool, bool]:
    try:
        address = ipaddress.ip_address(str(raw or "").strip())
    except ValueError:
        return False, False
    return True, bool(address.is_loopback or address.is_private)


def trusted_proxy_networks() -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
    networks = [
        ipaddress.ip_network("127.0.0.0/8"),
        ipaddress.ip_network("::1/128"),
        ipaddress.ip_network("::ffff:127.0.0.0/104"),
    ]
    for token in os.getenv("ARES_WEBUI_TRUSTED_PROXY_CIDRS", "").replace(";", ",").split(","):
        token = token.strip()
        if not token:
            continue
        try:
            networks.append(ipaddress.ip_network(token, strict=False))
        except ValueError:
            continue
    return networks


def ip_in_networks(address: Any, networks: list[Any]) -> bool:
    candidates = [address]
    mapped = getattr(address, "ipv4_mapped", None)
    if mapped is not None:
        candidates.append(mapped)
    for candidate in candidates:
        for network in networks:
            try:
                if candidate in network:
                    return True
            except TypeError:
                continue
    return False


def raw_peer_is_trusted_proxy(connection: Any) -> bool:
    try:
        address = ipaddress.ip_address(request_client_ip(connection))
    except ValueError:
        return False
    return ip_in_networks(address, trusted_proxy_networks())


def _header_values(headers: Any, name: str) -> list[str]:
    if hasattr(headers, "get_all"):
        return list(headers.get_all(name) or [])
    if hasattr(headers, "getlist"):
        return list(headers.getlist(name) or [])
    value = headers.get(name, "")
    return [value] if value else []


def forwarded_client_ip_from_trusted_proxy(connection: Any) -> str | None:
    headers = connection.headers
    values = _header_values(headers, "X-Forwarded-For")
    hops = [token.strip() for value in values for token in str(value or "").split(",")]
    if values:
        if not any(hops):
            return None
        networks = trusted_proxy_networks()
        for hop in reversed(hops):
            if not hop:
                return None
            try:
                address = ipaddress.ip_address(hop)
            except ValueError:
                return None
            if ip_in_networks(address, networks):
                continue
            return hop
        return request_client_ip(connection)
    real_ip = str(headers.get("X-Real-IP", "") or "").strip()
    return real_ip or request_client_ip(connection)


def request_is_local(connection: Any) -> bool:
    trust_forwarded = truthy_env("ARES_WEBUI_TRUST_FORWARDED_FOR")
    if trust_forwarded and raw_peer_is_trusted_proxy(connection):
        client_ip = forwarded_client_ip_from_trusted_proxy(connection)
        if client_ip is None:
            return False
        parsed, local = ip_is_loopback_or_private(client_ip)
        return parsed and local

    raw = request_client_ip(connection)
    parsed, local = ip_is_loopback_or_private(raw)
    if not parsed:
        return False
    address = ipaddress.ip_address(raw.strip())
    if address.is_loopback:
        return True
    forwarded = bool(
        str(connection.headers.get("X-Forwarded-For", "") or "").strip()
        or str(connection.headers.get("X-Real-IP", "") or "").strip()
    )
    return False if forwarded else bool(local)


def onboarding_gate_allows(connection: Any, auth_enabled: bool | None = None) -> bool:
    if auth_enabled is None:
        from api.auth import is_auth_enabled

        auth_enabled = is_auth_enabled()
    return bool(
        auth_enabled
        or truthy_env("ARES_WEBUI_ONBOARDING_OPEN")
        or request_is_local(connection)
    )


def embedded_terminal_gate_allows(connection: Any, auth_enabled: bool | None = None) -> bool:
    """Apply the same explicit local-network policy to embedded shell access."""

    return onboarding_gate_allows(connection, auth_enabled=auth_enabled)


# Private compatibility aliases make existing security tests independently
# movable without retaining the route dispatcher as their state owner.
_truthy_env = truthy_env
_request_client_ip = request_client_ip
_ip_is_loopback_or_private = ip_is_loopback_or_private
_trusted_proxy_networks = trusted_proxy_networks
_ip_in_networks = ip_in_networks
_raw_peer_is_trusted_proxy = raw_peer_is_trusted_proxy
_forwarded_client_ip_from_trusted_proxy = forwarded_client_ip_from_trusted_proxy
_onboarding_request_is_local = request_is_local
_onboarding_gate_allows = onboarding_gate_allows
_embedded_terminal_gate_allows = embedded_terminal_gate_allows
