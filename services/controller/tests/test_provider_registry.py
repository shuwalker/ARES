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


def test_legacy_jaeger_provider_id_is_normalized_on_read(tmp_path):
    path = tmp_path / "providers.json"
    path.write_text(json.dumps({
        "schema_version": 1,
        "providers": {
            "jros_local": {
                "enabled": True,
                "kind": "runtime",
                "endpoint": "http://jaeger.example:8643",
            },
        },
    }), encoding="utf-8")

    registry = load_provider_registry(path)
    assert set(registry["providers"]) == {"jaeger_local"}
    assert provider_endpoint("jaeger_local", registry=registry) == "http://jaeger.example:8643"
    assert provider_endpoint("jros_local", registry=registry) == "http://jaeger.example:8643"


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


def test_capabilities_string_is_rejected_rather_than_split_into_characters(tmp_path):
    """A hand-edited scalar must not become one capability per letter.

    ``"conversation"`` is iterable, so the previous set-comprehension turned it
    into ten single-character capabilities that then passed validation.
    """
    path = tmp_path / "providers.json"
    saved = save_provider(
        "scalar_caps",
        {"enabled": True, "capabilities": "conversation"},
        path=path,
    )
    assert saved["capabilities"] == []

    listed = save_provider(
        "list_caps",
        {"enabled": True, "capabilities": ["conversation", "tools", "conversation"]},
        path=path,
    )
    assert listed["capabilities"] == ["conversation", "tools"]


def test_unreadable_registry_is_never_overwritten(tmp_path):
    """A parse failure must not be laundered into an empty registry.

    Reading a corrupt file as ``{}`` and then saving over it destroyed every
    configured provider with no error, so writes now refuse rather than erase.
    """
    from api.provider_registry import ProviderRegistryCorrupt

    path = tmp_path / "providers.json"
    save_provider("keep_me", {"enabled": True, "endpoint": "https://keep.example"}, path=path)
    intact = path.read_text(encoding="utf-8")

    path.write_text(intact[:-5], encoding="utf-8")  # truncated mid-object

    for attempt in (
        lambda: save_provider("new_one", {"enabled": True}, path=path),
        lambda: remove_provider("keep_me", path=path),
    ):
        try:
            attempt()
        except ProviderRegistryCorrupt:
            pass
        else:  # pragma: no cover - only reached if the guard regresses
            raise AssertionError("a corrupt registry was overwritten")

    assert path.read_text(encoding="utf-8") == intact[:-5]


def test_missing_registry_still_saves_cleanly(tmp_path):
    """The strict read must not turn "no file yet" into a failure."""
    path = tmp_path / "nested" / "providers.json"
    save_provider("first", {"enabled": True, "endpoint": "https://first.example"}, path=path)
    assert sorted(load_provider_registry(path)["providers"]) == ["first"]
