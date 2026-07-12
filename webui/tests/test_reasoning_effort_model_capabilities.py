"""Tests for model-aware reasoning effort chip visibility."""

from api import config as cfg


def test_cursor_acp_models_do_not_support_reasoning_effort_levels():
    assert cfg.resolve_model_reasoning_efforts(
        "cursor/composer-2.5",
        provider_id="cursor-acp",
    ) == []


def test_openai_codex_gpt5_supports_reasoning_effort_levels():
    efforts = cfg.resolve_model_reasoning_efforts(
        "gpt-5.5",
        provider_id="openai-codex",
    )
    assert "medium" in efforts
    assert "high" in efforts
    assert "xhigh" in efforts
    assert "max" not in efforts


def test_openai_codex_prefixed_gpt5_supports_reasoning_effort_levels():
    efforts = cfg.resolve_model_reasoning_efforts(
        "@openai-codex:gpt-5.5",
        provider_id="openai-codex",
    )
    assert "medium" in efforts
    assert "high" in efforts
    assert "xhigh" in efforts
    assert "max" not in efforts


def test_openai_codex_max_effort_is_clamped_before_streaming():
    assert cfg.coerce_reasoning_effort_for_model(
        "max",
        "gpt-5.5",
        provider_id="openai-codex",
    ) == "xhigh"


def test_unsupported_xhigh_degrades_to_high_not_disabled():
    # o1/o3/o4 on openai-codex cap at low/medium/high. A configured xhigh (or
    # max) must clamp DOWN to the highest supported level (high), not silently
    # disable reasoning by returning "".
    assert cfg.coerce_reasoning_effort_for_model(
        "xhigh",
        "o3-mini",
        provider_id="openai-codex",
    ) == "high"
    assert cfg.coerce_reasoning_effort_for_model(
        "max",
        "o3-mini",
        provider_id="openai-codex",
    ) == "high"


def test_coerce_never_escalates_above_configured_effort():
    # A supported lower effort is returned verbatim; coercion only degrades.
    assert cfg.coerce_reasoning_effort_for_model(
        "low",
        "gpt-5.5",
        provider_id="openai-codex",
    ) == "low"


def test_coerce_preserves_effort_for_unrecognized_model():
    # #3505 review: resolve_model_reasoning_efforts() returns [] for BOTH
    # known-unsupported AND simply-unrecognized models (custom providers,
    # aggregator-rewritten ids, brand-new releases). Coercion must NOT silently
    # drop a configured effort just because we don't recognize the model — that
    # would be a behavior change vs sending it verbatim (master). Preserve the
    # configured level for an empty/unknown capability set; the provider stays
    # the final authority. The known-bad CLAMP paths return a NON-empty set, so
    # they are unaffected (covered by the openai-codex tests above).
    assert cfg.coerce_reasoning_effort_for_model(
        "high",
        "some-unknown-model-xyz",
        provider_id="some-custom-provider",
    ) == "high"
    # #3505 default-deny refinement (maintainer 2026-07-11): 'max' is a supra-
    # ceiling WebUI-only level, so on an UNRECOGNIZED provider it degrades to
    # xhigh (a truly-unknown provider would 400 on max). All OTHER levels still
    # preserve verbatim below.
    assert cfg.coerce_reasoning_effort_for_model(
        "max",
        "brand-new-model-2099",
        provider_id="some-custom-provider",
    ) == "xhigh"
    # 'none' / unset still pass through unchanged for unknown models.
    assert cfg.coerce_reasoning_effort_for_model(
        "none", "some-unknown-model-xyz", provider_id="custom"
    ) == "none"
    assert cfg.coerce_reasoning_effort_for_model(
        "", "some-unknown-model-xyz", provider_id="custom"
    ) == ""


def test_github_copilot_gpt5_supports_reasoning_effort_levels():
    efforts = cfg.resolve_model_reasoning_efforts(
        "gpt-5.5",
        provider_id="github-copilot",
    )
    assert "medium" in efforts
    assert "high" in efforts


def test_openrouter_anthropic_models_keep_reasoning_effort_levels():
    efforts = cfg.resolve_model_reasoning_efforts(
        "anthropic/claude-sonnet-4.5",
        provider_id="openrouter",
    )
    assert "medium" in efforts
    assert "high" in efforts


def test_non_reasoning_http_models_hide_reasoning_effort_levels():
    assert cfg.resolve_model_reasoning_efforts(
        "meta-llama/llama-3.1-8b-instruct",
        provider_id="openrouter",
    ) == []


def test_get_reasoning_status_includes_supported_efforts(monkeypatch):
    monkeypatch.setattr(
        cfg,
        "resolve_model_reasoning_efforts",
        lambda *a, **k: ["low", "medium", "high"],
    )
    status = cfg.get_reasoning_status(
        model_id="gpt-5.5",
        provider_id="openai-codex",
    )
    assert status["supported_efforts"] == ["low", "medium", "high"]
    assert status["supports_reasoning_effort"] is True


def test_get_reasoning_status_for_reasoning_capable_model_has_no_max():
    status = cfg.get_reasoning_status(
        model_id="gpt-5.5",
        provider_id="openai-codex",
    )
    assert status["supported_efforts"] == ["minimal", "low", "medium", "high", "xhigh"]
    assert status["supports_reasoning_effort"] is True
    assert "max" not in status["supported_efforts"]


def test_get_reasoning_status_coerces_stale_max_to_xhigh(monkeypatch):
    """A previously-saved `agent.reasoning_effort: max` (no longer a valid effort)
    must be reported as the coerced `xhigh`, not the raw stale `max`, so the
    boot/status/chip read paths agree with what streaming actually sends."""
    monkeypatch.setattr(
        cfg,
        "_load_yaml_config_file",
        lambda *a, **k: {"agent": {"reasoning_effort": "max"}},
    )
    status = cfg.get_reasoning_status(
        model_id="gpt-5.5",
        provider_id="openai-codex",
    )
    assert status["reasoning_effort"] == "xhigh"
    assert status["reasoning_effort"] != "max"


def test_max_effort_degrades_to_xhigh_for_gemini():
    # Gemini's native ladder tops out below 'max'; its adapter would silently
    # treat an unknown 'max' as medium. A stored/CLI 'max' must degrade to xhigh
    # (the highest supported), not fall through to a worse level. (#4627 gate)
    for model in ("gemini-3-pro", "gemini-3-flash"):
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id=model, provider_id="gemini"
        ) == "xhigh", f"{model} max must degrade to xhigh"


def test_max_effort_degrades_to_xhigh_for_pre_adaptive_anthropic():
    # Pre-adaptive Claude (3.7 / 4.0-4.5) uses manual thinking whose budget table
    # lacks 'max' and falls back to 8k; 'max' must degrade to xhigh instead. (#4627 gate)
    for model in (
        "claude-3-7-sonnet", "claude-sonnet-4-5", "claude-haiku-4-5",
        # date-stamped legacy IDs the Anthropic adapter uses
        "claude-3-opus-20240229", "claude-3-5-sonnet-20241022",
        "claude-sonnet-4-20250514", "claude-opus-4-20250514",
    ):
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id=model, provider_id="anthropic"
        ) == "xhigh", f"{model} max must degrade to xhigh"


def test_max_effort_preserved_for_adaptive_anthropic_and_deepseek():
    # Adaptive Claude (4.6+) and DeepSeek genuinely support 'max' — it must NOT degrade.
    for model in ("claude-opus-4.6", "claude-sonnet-4.6", "claude-opus-4.7", "claude-opus-latest"):
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id=model, provider_id="anthropic"
        ) == "max", f"{model} must preserve max"
    assert cfg.coerce_reasoning_effort_for_model(
        "max", model_id="deepseek-reasoner", provider_id="deepseek"
    ) == "max"


def test_max_degrades_across_all_openai_family_lanes():
    # 'max' is WebUI-only; direct OpenAI, openai-api, and Azure Foundry GPT-5 all
    # cap at xhigh (o-series at high), not just openai-codex. (#4627 re-gate)
    for prov in ("openai", "openai-api", "azure-foundry", "openai-codex"):
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id="gpt-5.1", provider_id=prov
        ) == "xhigh", f"gpt-5 on {prov} must degrade max->xhigh"
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id="o3", provider_id=prov
        ) == "high", f"o-series on {prov} must degrade max->high"


def test_max_degrades_for_azure_bedrock_hosted_legacy_claude():
    # Legacy Claude via Azure Foundry / Bedrock is still pre-adaptive; the ceiling
    # follows the model, not just the provider name. (#4627 re-gate)
    for prov in ("azure-foundry", "bedrock"):
        assert cfg.coerce_reasoning_effort_for_model(
            "max", model_id="claude-sonnet-4-20250514", provider_id=prov
        ) == "xhigh", f"legacy Claude on {prov} must degrade max->xhigh"
    # adaptive Claude via azure preserves max
    assert cfg.coerce_reasoning_effort_for_model(
        "max", model_id="claude-opus-4.6", provider_id="azure-foundry"
    ) == "max"


def test_max_degrades_on_unknown_provider_but_other_levels_preserved():
    # #3505 default-deny refinement (maintainer call 2026-07-11): 'max' is above
    # the universal ceiling, so an unknown/custom provider (empty capability list)
    # must degrade 'max'->'xhigh' rather than send an unsupported level — while all
    # other levels keep the conservative preserve-verbatim behavior.
    assert cfg.coerce_reasoning_effort_for_model(
        "max", model_id="some-unknown-model", provider_id="customprovider"
    ) == "xhigh"
    # other levels still preserved verbatim for an unknown provider
    for eff in ("minimal", "low", "medium", "high", "xhigh"):
        assert cfg.coerce_reasoning_effort_for_model(
            eff, model_id="some-unknown-model", provider_id="customprovider"
        ) == eff, f"{eff} must be preserved verbatim on unknown provider (#3505)"


def test_max_only_offered_in_ui_when_actually_supported():
    # The dropdown gates on resolve_model_reasoning_efforts(): 'max' appears ONLY
    # for models whose supported list includes it (adaptive Claude, DeepSeek), and
    # is absent for legacy/capped models and unknown providers.
    assert "max" in cfg.resolve_model_reasoning_efforts("claude-opus-4.6", provider_id="anthropic")
    assert "max" in cfg.resolve_model_reasoning_efforts("deepseek-reasoner", provider_id="deepseek")
    assert "max" not in cfg.resolve_model_reasoning_efforts("claude-sonnet-4-5", provider_id="anthropic")
    assert "max" not in cfg.resolve_model_reasoning_efforts("gpt-5.1", provider_id="openai")
    assert "max" not in cfg.resolve_model_reasoning_efforts("gemini-3-pro", provider_id="gemini")


def test_datestamped_claude3_not_reasoning_capable_heuristic():
    # A bare, date-stamped Claude 3.0 id must NOT be treated as reasoning-capable
    # by the heuristic. The minor-version capture previously used `(\d+)`, which
    # swallowed the 8-digit date stamp ("...-20240229") as the minor version so
    # `major==3 and minor>=7` wrongly matched — surfacing reasoning-effort
    # controls for models that don't support them. Claude 3.0/3.5 have no
    # extended-thinking support; only 3.7+ (and 4.x) do.
    for model in (
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307",
        "claude-3-opus",
        "claude-3-5-sonnet-20241022",
    ):
        assert cfg._candidate_supports_reasoning(model) is False, (
            f"{model} must not be reasoning-capable (Claude 3.0/3.5 excluded)"
        )
    # 3.7+ and 4.x (including date-stamped builds) stay reasoning-capable.
    for model in (
        "claude-3-7-sonnet",
        "claude-3-7-sonnet-20250219",
        "claude-sonnet-4-5",
        "claude-opus-4-20250514",
        "claude-opus-4.6",
    ):
        assert cfg._candidate_supports_reasoning(model) is True, (
            f"{model} must remain reasoning-capable"
        )

