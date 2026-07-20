"""Schedule channel-delivery: honest 'not configured', real dispatch when set."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

WEBUI = Path(__file__).resolve().parents[1]
if str(WEBUI) not in sys.path:
    sys.path.insert(0, str(WEBUI))

from api import delivery_adapters  # noqa: E402
from api.schedule_scheduler import _deliver_result  # noqa: E402


@pytest.fixture(autouse=True)
def _clean_registry():
    delivery_adapters._reset_for_tests()
    yield
    delivery_adapters._reset_for_tests()


def test_local_delivery_is_success_noop():
    assert _deliver_result({"deliver": "local"}, "hi") is None
    assert _deliver_result({"deliver": ""}, "hi") is None
    assert _deliver_result({"deliver": "origin"}, "hi") is None


def test_unknown_destination_reports_error():
    err = _deliver_result({"deliver": "carrier_pigeon"}, "hi")
    assert err is not None and "unknown delivery destination" in err.lower()


def test_known_platform_without_adapter_is_not_configured():
    err = _deliver_result({"deliver": "telegram", "deliver_target": "@me"}, "hi")
    assert err is not None and "not configured" in err.lower()


def test_configured_adapter_missing_target_reports_error():
    delivery_adapters.register_delivery_adapter("telegram", lambda **k: None)
    err = _deliver_result({"deliver": "telegram"}, "hi")
    assert err is not None and "no delivery target" in err.lower()


def test_configured_adapter_delivers():
    sent = {}

    def adapter(target, content, job):
        sent["target"] = target
        sent["content"] = content

    delivery_adapters.register_delivery_adapter("telegram", adapter)
    err = _deliver_result({"deliver": "telegram", "deliver_target": "@me"}, "hello")
    assert err is None
    assert sent == {"target": "@me", "content": "hello"}


def test_adapter_failure_is_reported_not_swallowed_as_success():
    def boom(**k):
        raise RuntimeError("network down")

    delivery_adapters.register_delivery_adapter("discord", boom)
    err = _deliver_result({"deliver": "discord", "deliver_target": "#chan"}, "hello")
    assert err is not None and "failed" in err.lower()
