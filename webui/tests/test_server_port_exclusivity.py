"""Uvicorn relies on exclusive OS bind semantics for duplicate instances."""

from __future__ import annotations

import socket

import pytest

from bootstrap import build_uvicorn_argv


def test_launcher_never_enables_port_reuse():
    argv = build_uvicorn_argv("python", "127.0.0.1", 8787)
    assert "--reuse-port" not in argv
    assert "--fd" not in argv


def test_second_listener_cannot_bind_same_address():
    first = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    second = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        first.bind(("127.0.0.1", 0))
        first.listen(1)
        address = first.getsockname()
        with pytest.raises(OSError):
            second.bind(address)
    finally:
        first.close()
        second.close()
