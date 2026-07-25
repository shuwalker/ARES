"""OS-automation consent gate: deny-by-default, approve-to-run."""

from __future__ import annotations

import sys
import threading
import time
from pathlib import Path

import pytest

WEBUI = Path(__file__).resolve().parents[1]
if str(WEBUI) not in sys.path:
    sys.path.insert(0, str(WEBUI))

from api import os_automation_consent as consent  # noqa: E402


def test_no_session_denies_immediately():
    assert consent.require_os_automation_consent("", "do a thing") is False


def test_timeout_denies(monkeypatch):
    monkeypatch.setattr(consent, "CONSENT_TIMEOUT_SECONDS", 0.2)
    submitted = {}
    monkeypatch.setattr(
        "api.route_approvals.submit_pending",
        lambda sid, card: submitted.update(sid=sid, card=card),
    )
    # No decision ever arrives -> deny.
    assert consent.require_os_automation_consent("sess-1", "type into App") is False
    assert submitted["card"]["kind"] == "os_automation"


def test_missing_transport_denies(monkeypatch):
    # Simulate submit_pending raising (transport unavailable) -> deny.
    def boom(*a, **k):
        raise RuntimeError("no transport")

    monkeypatch.setattr("api.route_approvals.submit_pending", boom)
    assert consent.require_os_automation_consent("sess-2", "type into App") is False


@pytest.mark.parametrize("choice,expected", [("once", True), ("session", True), ("always", True), ("deny", False)])
def test_decision_controls_outcome(monkeypatch, choice, expected):
    monkeypatch.setattr(consent, "CONSENT_TIMEOUT_SECONDS", 5.0)
    captured = {}
    monkeypatch.setattr(
        "api.route_approvals.submit_pending",
        lambda sid, card: captured.update(approval_id=card["approval_id"]),
    )

    result_box = {}

    def run():
        result_box["result"] = consent.require_os_automation_consent("sess-3", "type into App")

    t = threading.Thread(target=run)
    t.start()
    # Wait for the card to be submitted, then deliver the decision.
    for _ in range(50):
        if "approval_id" in captured:
            break
        time.sleep(0.02)
    assert "approval_id" in captured
    consent.signal_decision(captured["approval_id"], choice)
    t.join(timeout=5.0)
    assert result_box["result"] is expected


def test_app_automation_backend_blocked_without_consent(monkeypatch):
    """AppAutomationBackend.run_turn must not reach osascript without consent."""
    from api.backends.cli_backends import AppAutomationBackend

    ran = {"osascript": False}

    def fake_run(*a, **k):
        ran["osascript"] = True
        raise AssertionError("osascript should never be called when consent is denied")

    monkeypatch.setattr("subprocess.run", fake_run)
    monkeypatch.setattr(
        "api.os_automation_consent.require_os_automation_consent",
        lambda *a, **k: False,
    )

    backend = AppAutomationBackend("SomeApp", ["type_message", "return"])
    result = backend.run_turn("hello", "sess-4")
    assert ran["osascript"] is False
    assert "denied" in (result.get("error") or "").lower()
