import api.ares_identity as identity
import api.persona as persona_api


def test_persona_names_apply_only_to_the_elected_jros_runtime(monkeypatch):
    def fake_load_persona(persona_id):
        assert persona_id == "anakin"
        return {"identity": {"display_name": "Anakin Skywalker"}, "name": "Anakin"}

    monkeypatch.setattr(persona_api, "load_persona", fake_load_persona)
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    unselected = identity.build_identity_payload(
        bot_name="Astra", backend="", persona_id="anakin"
    )
    jros = identity.build_identity_payload(
        bot_name="Astra", backend="jros", persona_id="anakin"
    )
    assert unselected["display_name"] == "Astra"
    assert unselected["identity_kind"] == "default"
    assert jros["display_name"] == "Anakin Skywalker"
    assert jros["identity_kind"] == "character"


def test_incomplete_setup_falls_back_to_jarvis(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    payload = identity.build_identity_payload(bot_name="Ares", backend="jros")

    assert payload["display_name"] == "Jarvis"
    assert payload["default_display_name"] == "Jarvis"


def test_backend_badges_describe_external_runtime_selection(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    assert "JROS" in identity.get_backend_badge_html("jros")
    assert "No runtime selected" in identity.get_backend_badge_html("ares")


def test_profile_label_still_overrides_default_assistant(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    payload = identity.build_identity_payload(
        profile="robotics", bot_name="Astra", backend="jros", persona_id="anakin"
    )

    assert payload["display_name"] == "Robotics"
