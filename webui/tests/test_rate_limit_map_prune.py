"""Browser-diagnostic rate-limit storage remains bounded and self-pruning."""

from __future__ import annotations

from collections import defaultdict, deque
import threading

from api.client_reports import rate_limited


def test_expired_client_bucket_is_reused_without_rejection(monkeypatch):
    import api.client_reports as reports

    clock = iter((1_000.0, 1_061.0))
    monkeypatch.setattr(reports.time, "monotonic", lambda: next(clock))
    buckets = defaultdict(deque)
    lock = threading.Lock()
    assert not rate_limited(buckets, lock, "client", limit=1, window=60.0)
    assert not rate_limited(buckets, lock, "client", limit=1, window=60.0)
    assert len(buckets["client"]) == 1


def test_active_client_is_rejected_at_limit(monkeypatch):
    import api.client_reports as reports

    monkeypatch.setattr(reports.time, "monotonic", lambda: 2_000.0)
    buckets = defaultdict(deque)
    lock = threading.Lock()
    assert not rate_limited(buckets, lock, "client", limit=1, window=60.0)
    assert rate_limited(buckets, lock, "client", limit=1, window=60.0)


def test_large_bucket_map_prunes_stale_clients(monkeypatch):
    import api.client_reports as reports

    now = 3_000.0
    monkeypatch.setattr(reports.time, "monotonic", lambda: now)
    buckets = defaultdict(deque)
    for index in range(4_097):
        buckets[f"stale-{index}"].append(now - 120.0)
    lock = threading.Lock()
    assert not rate_limited(buckets, lock, "fresh", limit=10, window=60.0)
    assert len(buckets) < 4_098
    assert list(buckets["fresh"]) == [now]
