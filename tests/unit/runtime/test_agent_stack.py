from ares.runtime.agent_stack import default_agent_stack, stack_status


def test_default_stack_names_required_layers():
    stack = default_agent_stack()
    assert stack.layer_names() == (
        "presence",
        "runtime",
        "memory",
        "perception",
        "reasoning",
        "tools",
        "approval",
        "workflows",
    )


def test_stack_centers_avatar_companion_before_autonomy():
    stack = default_agent_stack()
    assert "AI avatar companion" in stack.first_product
    assert "Unbounded autonomous AGI claims" in stack.non_goals


def test_stack_status_is_api_serializable():
    status = stack_status()
    assert status["name"] == "ARES 2"
    assert status["current_milestone"] == "avatar_companion_foundation"
    assert status["layer_count"] == 8
    assert status["layers"][0]["name"] == "presence"
