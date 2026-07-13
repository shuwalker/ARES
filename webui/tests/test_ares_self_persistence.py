import pathlib


REPO = pathlib.Path(__file__).parent.parent


def read(path: str) -> str:
    return (REPO / path).read_text(encoding="utf-8")


def test_self_persistence_contract_exports_durable_ares_layer():
    from api.ares_self_persistence import build_self_persistence_contract

    contract = build_self_persistence_contract({})

    assert contract["identity_owner"] == "active_runtime"
    assert contract["identity_policy"] == "projection-only"
    assert contract["backend_policy"] == "adapter-first"
    assert contract["fork_decision"] == "deferred"
    assert contract["prevents_redo_work"] is True
    assert contract["adapters"] == ["hermes", "jros"]
    assert "identity_projection" in contract["capabilities"]
    assert "self_audit" in contract["capabilities"]
    assert "promise_to_task_capture" in contract["capabilities"]
    assert "autonomous_follow_through" in contract["capabilities"]
    assert "embodied_presence" in contract["capabilities"]


def test_self_persistence_prompt_section_instructs_ares_not_backend():
    from api.ares_self_persistence import render_self_persistence_prompt

    prompt = render_self_persistence_prompt({"ares_backend": "hybrid"})

    assert "ARES owns the experience layer, permissions, and task continuity" in prompt
    assert "Hermes supplies the agent loop" in prompt
    assert "JROS supplies robotics, embodiment, and canonical persona identity" in prompt
    assert "ARES identity APIs are projections of the active runtime" in prompt
    assert "Do not bury task continuity inside a swappable backend" in prompt
    assert "Active backend mode: hybrid" in prompt


def test_self_persistence_route_is_registered_with_other_ares_routes():
    routes = read("api/routes.py")

    assert '"/api/ares/self-persistence"' in routes
    assert "build_self_persistence_contract" in routes


def test_streaming_wires_self_persistence_into_agent_prompt():
    streaming = read("api/streaming.py")

    assert "render_self_persistence_prompt" in streaming
    assert "should_inject_self_persistence" in streaming
    assert "_self_persistence_prompt" in streaming
