"""Ownership tests for the transport-neutral approval service."""

def test_route_approvals_imports():
    from api.route_approvals import submit_pending, _approval_sse_subscribers
    assert callable(submit_pending)
    assert isinstance(_approval_sse_subscribers, dict)


def test_pending_identity():
    from api.route_approvals import _pending

    assert isinstance(_pending, dict)


def test_lock_identity():
    from api.route_approvals import _lock

    assert hasattr(_lock, "acquire")


def test_sse_helpers_importable_from_route_approvals():
    """All SSE helpers must be importable directly from route_approvals."""
    from api.route_approvals import (
        _approval_sse_subscribe,
        _approval_sse_unsubscribe,
        _approval_sse_notify_locked,
        _approval_sse_notify,
    )
    assert callable(_approval_sse_subscribe)
    assert callable(_approval_sse_unsubscribe)
    assert callable(_approval_sse_notify_locked)
    assert callable(_approval_sse_notify)


def test_sse_state_and_helpers_share_one_owner():
    import api.route_approvals as ra

    assert isinstance(ra._approval_sse_subscribers, dict)
    assert callable(ra._approval_sse_subscribe)
    assert callable(ra._approval_sse_unsubscribe)
    assert callable(ra._approval_sse_notify_locked)
    assert callable(ra._approval_sse_notify)
    assert callable(ra.submit_pending)


def test_no_circular_import():
    """route_approvals must not import from api.routes (no circular dep)."""
    import pathlib
    src = (pathlib.Path(__file__).parent.parent / "api" / "route_approvals.py").read_text()
    assert "from api.routes" not in src, "route_approvals.py must not import from api.routes"
    assert "import api.routes" not in src, "route_approvals.py must not import api.routes"
