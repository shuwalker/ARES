import json
import logging

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _record(caplog, *, headers=None):
    caplog.set_level(logging.INFO, logger="webui.access")
    with TestClient(create_app()) as client:
        response = client.get("/api/health?credential=must-not-log", headers=headers or {})
    message = next(record.getMessage() for record in caplog.records if record.name == "webui.access")
    return response, json.loads(message.removeprefix("[webui] "))


def test_access_log_has_structured_request_context_without_query_secrets(caplog):
    response, record = _record(caplog)
    assert record["remote"] == "testclient"
    assert record["method"] == "GET"
    assert record["path"] == "/api/health"
    assert record["status"] == response.status_code
    assert isinstance(record["ms"], (int, float))
    assert "credential" not in json.dumps(record)


def test_access_log_includes_first_forwarded_address(caplog):
    _response, record = _record(
        caplog,
        headers={"X-Forwarded-For": "203.0.113.7, 198.51.100.9"},
    )
    assert record["forwarded_for"] == "203.0.113.7"
