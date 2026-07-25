"""Regression coverage for issue #2232 legacy CLI toolset aliases."""

from unittest import mock


def test_normalize_cli_toolsets_expands_legacy_ares_alias():
    from api.config import _normalize_cli_toolsets

    assert _normalize_cli_toolsets(["ares", "web"]) == [
        "ares-cli",
        "ares-api-server",
        "web",
    ]


def test_normalize_cli_toolsets_deduplicates_expanded_aliases():
    from api.config import _normalize_cli_toolsets

    assert _normalize_cli_toolsets(["ares", "ares-cli", "ares-api-server"]) == [
        "ares-cli",
        "ares-api-server",
    ]


def test_resolve_cli_toolsets_fallback_expands_legacy_ares_alias():
    import api.config as config

    cfg = {"platform_toolsets": {"cli": ["ares", "web"]}}
    with mock.patch("builtins.__import__", side_effect=ImportError("no ares cli")):
        assert config._resolve_cli_toolsets(cfg) == ["ares-cli", "ares-api-server", "web"]
