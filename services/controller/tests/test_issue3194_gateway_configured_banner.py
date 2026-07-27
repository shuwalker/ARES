"""Regression coverage for #3194 — two-container Docker first-deploy shows
"Gateway not configured" even though the gateway is running.

Reported by @chenghaopeng: after a fresh ``docker-compose.two-container.yml``
deploy, the WebUI banner says "Gateway not configured" while
``ares gateway status`` reports the gateway is running. The trigger is an
empty ``identity_map`` (no conversation has happened yet, so no session
metadata exists) combined with an ``alive is None`` health payload whose
``details.reason`` is ``gateway_stale_running_state`` (the gateway is up but
hasn't ticked ``updated_at`` recently enough for the freshness check).

Before the fix, ``/api/gateway/status`` set ``configured = bool(identity_map)``
on the ``alive is None`` branch, so an empty identity_map → ``configured=False``
→ the misleading banner. The fix recognizes that an ``alive is None`` payload
which still carries gateway metadata (a ``gateway_state`` detail, or a stale-
running / stale-stopped reason) proves the gateway IS configured.

Mirrors the FakeHandler isolation pattern in
``tests/test_gateway_status_agent_health.py``.
"""
from __future__ import annotations

def _call_gateway_status(monkeypatch, *, health_payload, identity_map=None):
    """Build the transport-neutral payload used by the FastAPI endpoint."""
    import api.gateway_status as gateway_status

    monkeypatch.setattr(gateway_status, "build_agent_health_payload", lambda: health_payload)
    monkeypatch.setattr(
        gateway_status, "load_gateway_session_identity_map", lambda: (identity_map or {})
    )
    monkeypatch.setattr(gateway_status, "gateway_session_metadata_path", lambda: __import__("pathlib").Path("/missing"))
    return gateway_status.gateway_status_payload()


def test_stale_running_with_empty_identity_map_is_configured(monkeypatch):
    """#3194 core case: gateway up but not yet ticked, no sessions yet.

    alive=None + reason=gateway_stale_running_state + empty identity_map must
    NOT report 'Gateway not configured'.
    """
    payload = {
        "alive": None,
        "details": {"state": "unknown", "reason": "gateway_stale_running_state",
                    "gateway_state": "running"},
    }
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})

    assert data["configured"] is True, (
        "A stale-running gateway with no conversations yet is still configured "
        "— the banner must not say 'Gateway not configured' (#3194)."
    )
    # No live tick / no sessions → not 'running' for the activity indicator,
    # but that's a separate signal from 'configured'.
    assert data["running"] is False


def test_gateway_state_running_detail_marks_configured(monkeypatch):
    """An alive=None payload whose details report gateway_state == 'running'
    is configured, even if the reason string differs — the running metadata
    is the signal."""
    payload = {
        "alive": None,
        "details": {"state": "unknown", "reason": "cross_container_freshness",
                    "gateway_state": "running"},
    }
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})
    assert data["configured"] is True


def test_stale_stopped_with_empty_identity_map_not_configured(monkeypatch):
    """No-regression for #1944: a stale-STOPPED gateway must NOT report
    configured when there's no traffic. agent_health emits
    gateway_stale_stopped_state precisely so a stopped service the user isn't
    running reads like 'no root gateway configured' rather than nagging.
    Only stale-RUNNING metadata flips configured=True (#3194)."""
    payload = {
        "alive": None,
        "details": {"state": "unknown", "reason": "gateway_stale_stopped_state",
                    "gateway_state": "stopped"},
    }
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})
    assert data["configured"] is False
    assert data["running"] is False


def test_truly_unconfigured_stays_unconfigured(monkeypatch):
    """No-regression guard: alive=None with reason=gateway_not_configured and
    no metadata and no identity_map → genuinely not configured."""
    payload = {
        "alive": None,
        "details": {"state": "unknown", "reason": "gateway_not_configured"},
    }
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})
    assert data["configured"] is False
    assert data["running"] is False


def test_unconfigured_but_with_sessions_still_configured(monkeypatch):
    """Pre-existing behavior preserved: even with no gateway metadata, a
    non-empty identity_map implies a configured gateway."""
    payload = {
        "alive": None,
        "details": {"state": "unknown", "reason": "gateway_not_configured"},
    }
    idmap = {"sid-1": {"platform": "telegram", "raw_source": "telegram"}}
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map=idmap)
    assert data["configured"] is True
    assert data["running"] is True


def test_alive_true_unaffected(monkeypatch):
    """A live gateway is configured + running regardless of identity_map."""
    payload = {"alive": True, "details": {"state": "alive"}}
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})
    assert data["configured"] is True
    assert data["running"] is True


def test_alive_false_configured_not_running(monkeypatch):
    """alive=False (metadata exists, process down) stays configured-but-down."""
    payload = {"alive": False, "details": {"state": "down", "reason": "gateway_not_running"}}
    data = _call_gateway_status(monkeypatch, health_payload=payload, identity_map={})
    assert data["configured"] is True
    assert data["running"] is False
