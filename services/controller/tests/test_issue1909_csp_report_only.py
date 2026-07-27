"""FastAPI CSP report-only header and collector coverage (#1909)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from api import client_reports
from fastapi_app.main import create_app
from fastapi_app.security import REPORT_TO


def test_every_response_adds_report_only_policy():
    with TestClient(create_app()) as client:
        response = client.get("/api/health")
    policy = response.headers["content-security-policy-report-only"]
    assert response.headers["report-to"] == REPORT_TO
    assert "default-src 'self'" in policy
    assert "object-src 'none'" in policy
    assert "frame-ancestors 'none'" in policy
    assert "report-uri /api/csp-report" in policy
    assert "report-to csp-endpoint" in policy
    assert "'unsafe-eval'" not in policy


def test_csp_report_collector_accepts_both_browser_formats(caplog):
    client_reports._CSP_EVENTS.clear()
    with TestClient(create_app()) as client, caplog.at_level("INFO", logger="csp_report"):
        report_uri = client.post(
            "/api/csp-report",
            headers={"Content-Type": "application/csp-report"},
            json={"csp-report": {"violated-directive": "script-src-elem", "blocked-uri": "inline"}},
        )
        report_to = client.post(
            "/api/csp-report",
            headers={"Content-Type": "application/reports+json"},
            json=[{"type": "csp-violation", "body": {"blockedURL": "https://example.invalid/a.js"}}],
        )
    assert report_uri.status_code == 204
    assert report_to.status_code == 204
    assert "violated-directive" in caplog.text


def test_csp_report_collector_is_auth_and_csrf_exempt(monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: True)
    with TestClient(create_app()) as client:
        response = client.post("/api/csp-report", json={})
    assert response.status_code == 204


def test_csp_report_collector_rate_limits_without_rejecting(monkeypatch, caplog):
    client_reports._CSP_EVENTS.clear()
    monkeypatch.setattr(client_reports, "_CSP_LIMIT", 1)
    with TestClient(create_app()) as client, caplog.at_level("INFO", logger="csp_report"):
        first = client.post("/api/csp-report", json={"sequence": 1})
        second = client.post("/api/csp-report", json={"sequence": 2})
    assert first.status_code == second.status_code == 204
    assert caplog.text.count("CSP report from") == 1
