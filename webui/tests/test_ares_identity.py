import api.ares_identity as identity
import api.persona as persona_api


def test_persona_names_apply_to_jros_and_hybrid_not_ares(monkeypatch):
    def fake_load_persona(persona_id):
        assert persona_id == "anakin"
        return {"identity": {"display_name": "Anakin Skywalker"}, "name": "Anakin"}

    monkeypatch.setattr(persona_api, "load_persona", fake_load_persona)
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    ares = identity.build_identity_payload(
        bot_name="Astra", backend="ares", persona_id="anakin"
    )
    jros = identity.build_identity_payload(
        bot_name="Astra", backend="jros", persona_id="anakin"
    )
    hybrid = identity.build_identity_payload(
        bot_name="Astra", backend="hybrid", persona_id="anakin"
    )

    assert ares["display_name"] == "Astra"
    assert ares["identity_kind"] == "default"
    assert jros["display_name"] == "Anakin Skywalker"
    assert jros["identity_kind"] == "character"
    assert hybrid["display_name"] == "Anakin Skywalker"
    assert hybrid["identity_kind"] == "character"


def test_incomplete_setup_falls_back_to_jarvis(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    payload = identity.build_identity_payload(bot_name="Ares", backend="jros")

    assert payload["display_name"] == "Jarvis"
    assert payload["default_display_name"] == "Jarvis"


def test_backend_badges_are_runtime_badges(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    assert "Ares" in identity.get_backend_badge_html("ares")
    assert "JROS" in identity.get_backend_badge_html("jros")
    assert "Hybrid" in identity.get_backend_badge_html("hybrid")


def test_profile_label_still_overrides_default_assistant(monkeypatch):
    monkeypatch.setattr(identity, "_jros_default_agent_name", lambda: None)

    payload = identity.build_identity_payload(
        profile="robotics", bot_name="Astra", backend="jros", persona_id="anakin"
    )

    assert payload["display_name"] == "Robotics"
