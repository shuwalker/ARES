import logging
import types

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_uvicorn_shutdown_audit_logs_active_stream_context(monkeypatch, caplog):
    from api import models, shutdown_audit

    monkeypatch.setattr(shutdown_audit, "_LOGGED", False)
    monkeypatch.setitem(
        models.SESSIONS,
        "session-1\nforged",
        types.SimpleNamespace(active_stream_id="stream-1\rforged", pending_user_message="hello"),
    )
    monkeypatch.setitem(
        models.SESSIONS,
        "session-2",
        types.SimpleNamespace(active_stream_id=None, pending_user_message=None),
    )
    caplog.set_level(logging.INFO, logger="server")
    shutdown_audit.log_shutdown_audit(reason="test-exit")
    logged = "\n".join(record.getMessage() for record in caplog.records)
    assert "[shutdown-audit]" in logged
    assert "reason=test-exit" in logged
    assert "sid=session-1?forged stream=stream-1?forged pending=True" in logged
    assert "session-1\nforged" not in logged
    assert "session-2" not in logged


def test_shutdown_route_logs_request_without_killing_test_process(monkeypatch, caplog):
    from fastapi_app.routers import maintenance

    scheduled = []
    monkeypatch.setattr(maintenance, "_schedule_shutdown", lambda: scheduled.append(True))
    caplog.set_level(logging.INFO, logger="fastapi_app.routers.maintenance")
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/shutdown",
            headers={"User-Agent": "pytest-agent"},
        )
    assert response.status_code == 200
    assert response.json() == {"status": "shutting_down"}
    assert scheduled == [True]
    logged = "\n".join(record.getMessage() for record in caplog.records)
    assert "[shutdown-request]" in logged
    assert "remote=testclient" in logged
    assert "method=POST" in logged
    assert "path=/api/shutdown" in logged
    assert "ua=pytest-agent" in logged


def test_shutdown_log_values_strip_control_characters():
    from api.shutdown_audit import safe_log_value

    assert safe_log_value("pytest-agent\r\nforged") == "pytest-agent?forged"
