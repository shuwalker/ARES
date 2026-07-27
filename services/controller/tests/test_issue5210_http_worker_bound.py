"""Uvicorn launch remains concurrency- and backlog-bounded (#5210)."""

from bootstrap import build_uvicorn_argv


def _option(argv, name):
    return argv[argv.index(name) + 1]


def test_default_uvicorn_limits_are_explicit(monkeypatch):
    monkeypatch.delenv("ARES_WEBUI_MAX_CONCURRENCY", raising=False)
    monkeypatch.delenv("ARES_WEBUI_BACKLOG", raising=False)
    argv = build_uvicorn_argv("python", "127.0.0.1", 8787)
    assert argv[:4] == ["python", "-m", "uvicorn", "fastapi_app.main:app"]
    assert _option(argv, "--limit-concurrency") == "128"
    assert _option(argv, "--backlog") == "64"
    assert _option(argv, "--timeout-keep-alive") == "30"


def test_operator_can_lower_or_raise_limits(monkeypatch):
    monkeypatch.setenv("ARES_WEBUI_MAX_CONCURRENCY", "32")
    monkeypatch.setenv("ARES_WEBUI_BACKLOG", "16")
    argv = build_uvicorn_argv("python", "0.0.0.0", 9000)
    assert _option(argv, "--limit-concurrency") == "32"
    assert _option(argv, "--backlog") == "16"


def test_tls_flags_are_added_as_a_pair():
    argv = build_uvicorn_argv(
        "python",
        "127.0.0.1",
        8787,
        tls_cert="cert.pem",
        tls_key="key.pem",
    )
    assert _option(argv, "--ssl-certfile") == "cert.pem"
    assert _option(argv, "--ssl-keyfile") == "key.pem"
