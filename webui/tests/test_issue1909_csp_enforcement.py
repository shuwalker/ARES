"""FastAPI CSP enforcement and report-only alignment (#1909)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.security import REPORT_TO


def _directives(policy: str) -> dict[str, str]:
    return {
        key: value.strip()
        for entry in policy.split(";")
        if entry.strip()
        for key, _, value in [entry.strip().partition(" ")]
    }


def _headers():
    with TestClient(create_app()) as client:
        return client.get("/api/health").headers


def test_fastapi_response_enforces_csp_and_baseline_headers(monkeypatch):
    monkeypatch.delenv("ARES_WEBUI_CSP_CONNECT_EXTRA", raising=False)
    headers = _headers()
    policy = headers["content-security-policy"]
    assert "default-src 'self' https://*.cloudflareaccess.com" in policy
    assert "object-src 'none'" in policy
    assert "frame-ancestors 'none'" in policy
    assert "base-uri 'self'" in policy
    assert "form-action 'self'" in policy
    assert "worker-src blob: 'self' https://cdn.jsdelivr.net" in policy
    assert "connect-src 'self' http://127.0.0.1:* http://localhost:*" in policy
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "DENY"
    assert headers["referrer-policy"] == "same-origin"


def test_enforced_and_report_only_policies_share_directives(monkeypatch):
    monkeypatch.setenv("ARES_WEBUI_CSP_CONNECT_EXTRA", "https://metrics.example.com")
    headers = _headers()
    enforced = _directives(headers["content-security-policy"])
    report_only = _directives(headers["content-security-policy-report-only"])
    assert "https://metrics.example.com" in enforced["connect-src"]
    assert report_only.pop("report-uri") == "/api/csp-report"
    assert report_only.pop("report-to") == "csp-endpoint"
    assert report_only == enforced
    assert headers["report-to"] == REPORT_TO


def test_valid_frame_and_connect_extras_are_independent(monkeypatch):
    monkeypatch.setenv("ARES_WEBUI_CSP_FRAME_EXTRA", "https://dash.example.com")
    monkeypatch.setenv("ARES_WEBUI_CSP_CONNECT_EXTRA", "wss://events.example.com:443")
    policy = _directives(_headers()["content-security-policy"])
    assert "https://dash.example.com" in policy["frame-src"]
    assert "dash.example.com" not in policy["connect-src"]
    assert "wss://events.example.com:443" in policy["connect-src"]


def test_invalid_extra_is_rejected_once_per_response(monkeypatch, caplog):
    monkeypatch.setenv("ARES_WEBUI_CSP_CONNECT_EXTRA", "https://ok.example; script-src *")
    headers = _headers()
    assert "https://ok.example" not in headers["content-security-policy"]
    assert "script-src *" not in headers["content-security-policy"]
    assert "Ignoring invalid ARES_WEBUI_CSP_CONNECT_EXTRA" in caplog.text
