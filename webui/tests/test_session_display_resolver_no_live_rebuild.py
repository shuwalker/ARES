"""Session display remains a side-effect-free FastAPI read."""

from __future__ import annotations

from fastapi.testclient import TestClient
import pytest

import api.config as config
from fastapi_app.main import create_app


class _CoreService:
    def session(self, session_id, **_kwargs):
        return {
            "session": {
                "session_id": session_id,
                "title": "Cached session",
                "workspace": "",
                "messages": [],
                "model": "claude-opus-4-7",
                "model_provider": None,
            }
        }


@pytest.mark.parametrize("load_messages", [True, False])
def test_session_read_never_rebuilds_live_model_catalog(monkeypatch, load_messages):
    calls = {"count": 0}

    def fail_if_called(_builder):
        calls["count"] += 1
        raise AssertionError("GET /api/session must not rebuild the live model catalog")

    monkeypatch.setattr(config, "_invoke_models_rebuild", fail_if_called)
    app = create_app(core_service=_CoreService())
    with TestClient(app) as client:
        response = client.get(
            "/api/session",
            params={"session_id": "display-test", "messages": str(load_messages).lower()},
        )
    assert response.status_code == 200
    assert response.json()["session"]["model"] == "claude-opus-4-7"
    assert calls["count"] == 0
