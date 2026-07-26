"""Hermes readiness — the single source of truth for "is Hermes usable".

Both registries call this: ``HermesAdapter.check_health`` (the adapter registry
behind ``/api/connections``) and ``HermesBackend.is_available`` (the older
backend router behind ``/api/backends``). They previously ran their own probes
and could drift; routing both through one function makes disagreement
impossible.

Hermes runs as a local CLI, so it has no ``not_configured`` case today — there
is no key or endpoint to set. If the HTTP-gateway transport later becomes the
primary path for Hermes, that branch belongs here.
"""
from __future__ import annotations

from api.providers.status_contract import ProviderStatus, connected, not_installed, offline

_INSTALL_HINT = (
    "Hermes Agent CLI not found. Install with: "
    "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
)


def check_status() -> ProviderStatus:
    """Probe the Hermes CLI and describe what a user would need to do."""
    from api.providers.hermes.backend import _available_message, _probe_hermes

    try:
        found, version = _probe_hermes()
    except Exception as exc:
        # A failing probe is a real runtime condition, not a crash: report it
        # rather than letting it propagate into every health-listing endpoint.
        return offline(f"Hermes Agent could not be probed: {exc}")

    if not found:
        return not_installed(_INSTALL_HINT)
    return connected(_available_message(version), version=version)
