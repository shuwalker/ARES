"""Bounded, sanitized browser diagnostics collectors."""

from __future__ import annotations

from collections import defaultdict, deque
import json
import logging
import threading
import time
from typing import Any


_CSP_LIMIT = 100
_CSP_WINDOW_SECONDS = 60.0
_CSP_MAX_BYTES = 64 * 1024
_CSP_EVENTS: dict[str, deque[float]] = defaultdict(deque)
_CSP_LOCK = threading.Lock()

_CLIENT_LIMIT = 30
_CLIENT_WINDOW_SECONDS = 60.0
_CLIENT_MAX_BYTES = 4 * 1024
_CLIENT_EVENTS: dict[str, deque[float]] = defaultdict(deque)
_CLIENT_LOCK = threading.Lock()

_CLIENT_FIELDS = {
    "event": 64,
    "source": 80,
    "session_id": 128,
    "stream_id": 128,
    "visibility_state": 32,
    "url_path": 256,
    "reason": 160,
}


def rate_limited(
    buckets: dict[str, deque[float]],
    lock: threading.Lock,
    client: str,
    *,
    limit: int,
    window: float,
) -> bool:
    now = time.monotonic()
    with lock:
        bucket = buckets[client]
        while bucket and now - bucket[0] >= window:
            bucket.popleft()
        if len(bucket) >= limit:
            return True
        bucket.append(now)
        if len(buckets) > 4096:
            for key in list(buckets)[:1024]:
                if not buckets[key] or now - buckets[key][-1] >= window:
                    buckets.pop(key, None)
        return False


def record_csp_report(client: str, raw: bytes) -> None:
    if rate_limited(
        _CSP_EVENTS,
        _CSP_LOCK,
        client,
        limit=_CSP_LIMIT,
        window=_CSP_WINDOW_SECONDS,
    ):
        return
    try:
        payload: Any = json.loads(raw[:_CSP_MAX_BYTES].decode("utf-8"))
    except (UnicodeError, ValueError):
        payload = {"invalid": True}
    # CSP reports are browser-generated but can contain full URLs. Logging the
    # structured report is useful; never log cookies, authorization headers, or
    # arbitrary request bytes.
    logging.getLogger("csp_report").info("CSP report from %s: %s", client, payload)


def record_client_event(client: str, raw: bytes) -> None:
    if rate_limited(
        _CLIENT_EVENTS,
        _CLIENT_LOCK,
        client,
        limit=_CLIENT_LIMIT,
        window=_CLIENT_WINDOW_SECONDS,
    ):
        return
    try:
        payload = json.loads(raw[:_CLIENT_MAX_BYTES].decode("utf-8"))
    except (UnicodeError, ValueError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    sanitized = {
        key: str(payload[key])[:limit]
        for key, limit in _CLIENT_FIELDS.items()
        if payload.get(key) is not None
    }
    logging.getLogger("client_event").info("Client event from %s: %s", client, sanitized)


__all__ = [
    "_CLIENT_EVENTS",
    "_CSP_EVENTS",
    "record_client_event",
    "record_csp_report",
]
