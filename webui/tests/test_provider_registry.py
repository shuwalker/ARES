import json

from api.provider_registry import (
    configured_provider,
    empty_registry,
    load_provider_registry,
    provider_endpoint,
    provider_registry_path,
    remove_provider,
    save_provider,
)


def test_missing_registry_is_empty_and_does_not_assume_provider_ports(tmp_path):
    path = tmp_path / "providers.json"
    assert load_provider_registry(path) == empty_registry()
    assert provider_endpoint("hermes_local", registry=empty_registry()) == ""
    assert provider_endpoint("jros_local", registry=empty_registry()) == ""


def test_registry_keeps_only_normalized_non_secret_connection_metadata(tmp_path):
    path = tmp_path / "providers.json"
    path.write_text(json.dumps({
        "schema_version": 1,
        "providers": {
            "Hermes_Local": {
                "enabled": True,
                "kind": "runtime",
                "endpoint": "http://hermes-owned.example:9999/",
                "credential_env": "HERMES_API_KEY",
                "capabilities": ["conversation", "conversation", "tools"],
                "metadata": {"managed_by": "hermes"},
                "api_key": "must-not-be-copied",
            },
            "invalid": {"enabled": True, "endpoint": "file:///tmp/socket"},
        },
    }), encoding="utf-8")

    registry = load_provider_registry(path)
    hermes = configured_provider("hermes_local", registry=registry)
    assert hermes == {
        "id": "hermes_local",
        "enabled": True,
        "kind": "runtime",
        "endpoint": "http://hermes-owned.example:9999",
        "credential_env": "HERMES_API_KEY",
        "capabilities": ["conversation", "tools"],
        "metadata": {"managed_by": "hermes"},
    }
    assert provider_endpoint("invalid", registry=registry) == ""
    assert "api_key" not in hermes


def test_disabled_provider_is_not_connected():
    registry = {
        "schema_version": 1,
        "providers": {
            "openclaw_local": {
                "id": "openclaw_local",
                "enabled": False,
                "endpoint": "http://openclaw.example:7000",
            }
        },
    }
    assert configured_provider("openclaw_local", registry=registry) is None


def test_registry_path_is_ares_owned_and_overrideable(tmp_path):
    override = tmp_path / "connections.json"
    assert provider_registry_path({"ARES_PROVIDER_REGISTRY_PATH": str(override)}) == override


def test_provider_can_be_saved_and_removed_without_secret_values(tmp_path):
    path = tmp_path / "providers.json"
    saved = save_provider("openclaw_local", {
        "enabled": True,
        "endpoint": "http://openclaw-owned.example:7000",
        "credential_env": "OPENCLAW_TOKEN",
        "token": "never-persist-this",
    }, path=path)
    assert saved["id"] == "openclaw_local"
    raw = path.read_text(encoding="utf-8")
    assert "never-persist-this" not in raw
    assert provider_endpoint("openclaw_local", registry=load_provider_registry(path)) == (
        "http://openclaw-owned.example:7000"
    )
    assert remove_provider("openclaw_local", path=path) is True
    assert load_provider_registry(path)["providers"] == {}
