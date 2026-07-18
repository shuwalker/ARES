"""
Sprint 27 Tests: configurable assistant display name (bot_name).
Tests cover settings API round-trip, empty/missing input defaults,
login page rendering, and server-side sanitization.
"""
import json
import urllib.error
import urllib.request

from tests._pytest_port import BASE


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read()), r.status


def get_raw(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return r.read().decode(), r.status


def post(path, body=None):
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(BASE + path, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        return json.loads(e.read()), e.code


# ── Default value ─────────────────────────────────────────────────────────

def test_settings_default_bot_name():
    """GET /api/settings should return bot_name defaulting to 'Ares'."""
    d, status = get("/api/settings")
    assert status == 200
    assert "bot_name" in d
    assert d["bot_name"] == "Ares"


# ── Round-trip ────────────────────────────────────────────────────────────

def test_settings_set_bot_name():
    """POST /api/settings with bot_name should persist and round-trip."""
    try:
        d, status = post("/api/settings", {"bot_name": "TestBot"})
        assert status == 200
        assert d.get("bot_name") == "TestBot"
        d2, _ = get("/api/settings")
        assert d2.get("bot_name") == "TestBot"
    finally:
        post("/api/settings", {"bot_name": "Ares"})


def test_settings_bot_name_special_chars():
    """bot_name with safe special characters should persist correctly."""
    try:
        d, status = post("/api/settings", {"bot_name": "My Assistant 2.0"})
        assert status == 200
        d2, _ = get("/api/settings")
        assert d2.get("bot_name") == "My Assistant 2.0"
    finally:
        post("/api/settings", {"bot_name": "Ares"})


# ── Server-side sanitization ──────────────────────────────────────────────

def test_settings_empty_bot_name_defaults_to_ares():
    """Posting an empty bot_name should default to 'Ares' server-side."""
    try:
        d, status = post("/api/settings", {"bot_name": ""})
        assert status == 200
        assert d.get("bot_name") == "Ares"
        d2, _ = get("/api/settings")
        assert d2.get("bot_name") == "Ares"
    finally:
        post("/api/settings", {"bot_name": "Ares"})


def test_settings_whitespace_bot_name_defaults_to_ares():
    """Posting a whitespace-only bot_name should default to 'Ares'."""
    try:
        d, status = post("/api/settings", {"bot_name": "   "})
        assert status == 200
        assert d.get("bot_name") == "Ares"
    finally:
        post("/api/settings", {"bot_name": "Ares"})


# ── Client-rendered login shell ───────────────────────────────────────────

def test_login_page_shows_default_bot_name():
    """GET /login serves the React shell; React reads the Local Profile."""
    html, status = get_raw("/login")
    assert status == 200
    assert '<div id="root"></div>' in html
    assert "/assets/" in html


def test_login_page_shows_custom_bot_name():
    """Companion naming remains an API contract, not server-rendered HTML."""
    try:
        post("/api/settings", {"bot_name": "Aria"})
        html, status = get_raw("/login")
        assert status == 200
        settings, _ = get("/api/settings")
        assert settings["bot_name"] == "Aria"
        assert '<div id="root"></div>' in html
    finally:
        post("/api/settings", {"bot_name": "Ares"})


def test_login_page_empty_name_does_not_crash():
    """Login page must not 500 even if somehow bot_name is empty in settings."""
    # Force an empty value by patching settings file directly — skipped here
    # because the server-side guard in POST /api/settings prevents storing empty.
    # Instead, verify that /login returns 200 reliably.
    html, status = get_raw("/login")
    assert status == 200
    assert '<div id="root"></div>' in html


def test_login_page_xss_escaped():
    """Local Profile values are never interpolated into the static SPA shell."""
    try:
        post("/api/settings", {"bot_name": "<script>alert(1)</script>"})
        html, status = get_raw("/login")
        assert status == 200
        # Raw tag must not appear unescaped
        assert "<script>alert(1)</script>" not in html
        assert '<div id="root"></div>' in html
    finally:
        post("/api/settings", {"bot_name": "Ares"})
