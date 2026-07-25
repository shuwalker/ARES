"""Behavioral coverage for the FastAPI session-duplicate contract."""

from __future__ import annotations

import json
import urllib.request

from tests.conftest import TEST_BASE, _post


def _get(path: str) -> dict:
    with urllib.request.urlopen(TEST_BASE + path, timeout=10) as response:
        return json.loads(response.read())


def test_duplicate_session_requires_session_id(cleanup_test_sessions):
    assert "error" in _post(TEST_BASE, "/api/session/duplicate", {})
    assert "error" in _post(
        TEST_BASE,
        "/api/session/duplicate",
        {"session_id": ""},
    )


def test_duplicate_session_returns_not_found_for_unknown_id(cleanup_test_sessions):
    result = _post(
        TEST_BASE,
        "/api/session/duplicate",
        {"session_id": "nonexistent_xyz"},
    )
    assert result.get("error")


def test_duplicate_route_is_registered_on_fastapi_router():
    from fastapi_app.routers.session import router

    routes = {(method, route.path) for route in router.routes for method in route.methods}
    assert ("POST", "/api/session/duplicate") in routes


def test_duplicate_is_durable_and_independent(cleanup_test_sessions):
    imported = _post(
        TEST_BASE,
        "/api/session/import",
        {
            "title": "Source",
            "model": "test/model",
            "messages": [
                {"role": "user", "content": "hello"},
                {"role": "assistant", "content": "world"},
            ],
        },
    )["session"]
    source_id = imported["session_id"]
    cleanup_test_sessions.append(source_id)

    copied = _post(
        TEST_BASE,
        "/api/session/duplicate",
        {"session_id": source_id},
    )["session"]
    copied_id = copied["session_id"]
    cleanup_test_sessions.append(copied_id)

    assert copied_id != source_id
    assert copied["title"] == "Source (copy)"
    assert copied["messages"] == imported["messages"]
    assert copied["model"] == imported["model"]
    assert copied["workspace"] == imported["workspace"]
    assert copied.get("parent_session_id") is None
    assert copied.get("pinned") is False
    assert copied.get("archived") is False

    _post(
        TEST_BASE,
        "/api/session/rename",
        {"session_id": copied_id, "title": "Changed copy"},
    )
    source = _get(f"/api/session?session_id={source_id}")["session"]
    persisted_copy = _get(f"/api/session?session_id={copied_id}")["session"]
    assert source["title"] == "Source"
    assert persisted_copy["title"] == "Changed copy"
