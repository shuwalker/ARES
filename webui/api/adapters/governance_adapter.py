"""Agent Governance Toolkit adapter for policy enforcement.

Connects to an agent-governance-toolkit policy engine via its Python SDK
(installable via ``pip install agent-governance-toolkit``) to enforce
safety, permission, and behaviour policies on ARES actions before they
are dispatched to downstream devices or services.

Current status: **stub** — method bodies contain TODO markers where
actual SDK calls belong.
"""

from __future__ import annotations

import logging
from typing import Any

from .base import (
    AdapterDeviceError,
    BaseDeviceAdapter,
    DeviceCapability,
    DeviceConnectionState,
    DeviceDescriptor,
    DeviceHealth,
)

logger = logging.getLogger(__name__)

_DEFAULT_GOVERNANCE_URL = "http://localhost:8080"


class GovernanceAdapter(BaseDeviceAdapter):
    """Device adapter for the agent-governance-toolkit policy engine.

    Uses the governance SDK to evaluate action requests against configured
    policies (permissions, rate-limits, safety checks) and returns
    allow/deny decisions that ARES respects before executing commands.

    Parameters:
        url: Base URL of the governance policy engine service.
    """

    adapter_id = "governance"
    display_name = "Agent Governance Toolkit"
    kind = "governance"

    def __init__(
        self,
        url: str = _DEFAULT_GOVERNANCE_URL,
    ) -> None:
        self._url = url
        # TODO: initialise governance SDK client
        # from governance import Client
        # self._client = Client(base_url=url)
        self._devices: dict[str, DeviceDescriptor] = {}
        self._connected: dict[str, bool] = {}

    # ------------------------------------------------------------------
    # BaseDeviceAdapter contract
    # ------------------------------------------------------------------

    async def connect(self, device_id: str) -> DeviceDescriptor:
        """Connect to the governance policy engine.

        TODO: Authenticate with the governance service and load active
        policy sets for the given device_id / agent identity.
        """
        if device_id in self._connected and self._connected[device_id]:
            return self.device_info(device_id)

        logger.info("Connecting to governance engine %s at %s", device_id, self._url)

        # TODO: Replace with actual SDK connect:
        #   await self._client.authenticate(device_id)
        #   policies = await self._client.list_policies()

        descriptor = DeviceDescriptor(
            device_id=device_id,
            name=device_id,  # TODO: resolve from governance identity
            driver="governance",
            capability=DeviceCapability.SAFETY_MONITOR,  # closest semantic match
            adapter_kind="governance",
            connection_state=DeviceConnectionState.CONNECTING,
        )
        self._devices[device_id] = descriptor
        self._connected[device_id] = True

        self._devices[device_id] = DeviceDescriptor(
            **{**descriptor.as_dict(), "connection_state": DeviceConnectionState.CONNECTED},
        )
        return self._devices[device_id]

    async def disconnect(self, device_id: str) -> None:
        """Disconnect from the governance policy engine.

        TODO: Revoke session token and clean up SDK client state.
        """
        if device_id not in self._connected:
            return

        logger.info("Disconnecting governance device %s", device_id)
        # TODO: await self._client.revoke_session(device_id)
        self._connected[device_id] = False

        if device_id in self._devices:
            old = self._devices[device_id]
            self._devices[device_id] = DeviceDescriptor(
                **{**old.as_dict(), "connection_state": DeviceConnectionState.DISCONNECTED},
            )

    def health(self, device_id: str) -> DeviceHealth:
        """Report governance engine health.

        TODO: Ping the governance service health endpoint.
        """
        if device_id not in self._connected:
            return DeviceHealth(
                state=DeviceConnectionState.DISCONNECTED,
                available=False,
                message=f"Device {device_id} not known",
            )

        if self._connected.get(device_id, False):
            # TODO: read actual service health
            return DeviceHealth(
                state=DeviceConnectionState.CONNECTED,
                available=True,
                message="Governance engine connected",
            )

        return DeviceHealth(
            state=DeviceConnectionState.DISCONNECTED,
            available=False,
            message="Governance engine disconnected",
        )

    def capabilities(self, device_id: str) -> list[DeviceCapability]:
        """Return governance capabilities.

        TODO: Query the engine for supported policy types and map them.
        """
        if device_id not in self._devices:
            return []
        # TODO: derive from policy engine capabilities
        return [DeviceCapability.SAFETY_MONITOR]

    def device_info(self, device_id: str) -> DeviceDescriptor:
        """Return the current descriptor for *device_id*.

        Raises:
            AdapterDeviceError: If the device is unknown.
        """
        if device_id not in self._devices:
            raise AdapterDeviceError(
                404,
                f"Governance device not found: {device_id}",
                code="device_not_found",
            )
        return self._devices[device_id]

    async def discover(self) -> list[DeviceDescriptor]:
        """Discover available governance policy endpoints.

        TODO: Query the governance service for registered agents/policy sets.
        """
        logger.info("Discovering governance endpoints at %s", self._url)
        # TODO: await self._client.list_agents()
        return list(self._devices.values())

    # ------------------------------------------------------------------
    # Governance operations
    # ------------------------------------------------------------------

    async def evaluate_policy(self, device_id: str, action: str, context: dict[str, Any] | None = None) -> dict[str, Any]:
        """Evaluate an action against governance policies.

        TODO: Call governance SDK to check whether *action* is permitted
        given *context*, returning allow/deny with reason.
        """
        self._require_connected(device_id)
        logger.info("Governance evaluate_policy %s: action=%s", device_id, action)
        # TODO: result = await self._client.evaluate(action, context)
        return {"device_id": device_id, "action": action, "decision": "allow", "reason": "stub"}

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _require_connected(self, device_id: str) -> None:
        """Raise ``AdapterDeviceError`` if the device is not connected."""
        if not self._connected.get(device_id):
            raise AdapterDeviceError(
                409,
                f"Device {device_id} is not connected",
                code="device_not_connected",
            )