"""mDNS/UDP discovery for INDI servers and Alpaca devices on the network.

INDI servers are discovered by probing well-known ports (default 7624).
Alpaca devices are discovered via the Alpaca UDP discovery protocol
(broadcast on port 32227) or by probing configured server endpoints.

Current status: **stub** — discovery probes are placeholder implementations
that return empty results.  Actual network I/O will be wired in when the
async event loop integration is ready.
"""

from __future__ import annotations

import logging
from typing import Any

from .base import DeviceDescriptor

logger = logging.getLogger(__name__)

# Well-known defaults
_INDI_DEFAULT_PORT = 7624
_ALPACA_DISCOVERY_PORT = 32227
_ALPACA_DEFAULT_PORT = 11111


class DeviceDiscoveryService:
    """Aggregate discovery across INDI and Alpaca device servers.

    Parameters:
        indi_host: Hostname for INDI server probing.
        indi_port: Port for INDI server probing.
        alpaca_host: Hostname for Alpaca server probing.
        alpaca_port: Port for Alpaca server probing.
    """

    def __init__(
        self,
        *,
        indi_host: str = "localhost",
        indi_port: int = _INDI_DEFAULT_PORT,
        alpaca_host: str = "localhost",
        alpaca_port: int = _ALPACA_DEFAULT_PORT,
    ) -> None:
        self._indi_host = indi_host
        self._indi_port = indi_port
        self._alpaca_host = alpaca_host
        self._alpaca_port = alpaca_port

    async def discover_indi_servers(self) -> list[dict[str, Any]]:
        """Probe for INDI servers on the network.

        TODO: Implement mDNS service discovery or TCP port probe for INDI
        servers on port 7624.  Return a list of dicts with ``host``, ``port``,
        and ``devices`` keys.
        """
        logger.info("Discovering INDI servers (stub: checking %s:%d)", self._indi_host, self._indi_port)
        # TODO: actual mDNS / port probe
        # Stub: return the default local server if reachable
        return [
            {
                "host": self._indi_host,
                "port": self._indi_port,
                "devices": [],
            },
        ]

    async def discover_alpaca_servers(self) -> list[dict[str, Any]]:
        """Discover Alpaca servers via UDP broadcast.

        TODO: Send a UDP discovery packet to ``<broadcast>:32227``, parse
        the ``alpaca://host:port`` responses, then query each server's
        ``/api/v1/{device_type}`` endpoints to enumerate devices.
        """
        logger.info(
            "Discovering Alpaca servers (stub: checking %s:%d)",
            self._alpaca_host,
            self._alpaca_port,
        )
        # TODO: UDP broadcast discovery + REST enumeration
        return [
            {
                "host": self._alpaca_host,
                "port": self._alpaca_port,
                "devices": [],
            },
        ]

    async def discover_all(self) -> dict[str, list[dict[str, Any]]]:
        """Run both INDI and Alpaca discovery and return merged results.

        Returns:
            A dict with ``"indi"`` and ``"alpaca"`` keys, each containing
            the list of discovered server dicts.
        """
        indi_results = await self.discover_indi_servers()
        alpaca_results = await self.discover_alpaca_servers()
        return {
            "indi": indi_results,
            "alpaca": alpaca_results,
        }