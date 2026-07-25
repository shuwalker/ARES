"""Uvicorn process setup ignores SIGPIPE without breaking Windows."""

from __future__ import annotations

import signal

from api.process_runtime import ignore_sigpipe


def test_sigpipe_is_ignored_on_posix():
    result = ignore_sigpipe()
    if hasattr(signal, "SIGPIPE"):
        assert result is True
        assert signal.getsignal(signal.SIGPIPE) == signal.SIG_IGN
    else:
        assert result is False


def test_sigpipe_lookup_is_platform_guarded():
    import inspect

    source = inspect.getsource(ignore_sigpipe)
    assert 'getattr(signal, "SIGPIPE"' in source
    assert "SIG_IGN" in source
