"""Unit tests for the CognitiveSnapshot transport model.

These verify the shape that the WebSocket / REST API ships and that the
Swift client (in ARES-Face/Models/CognitiveSnapshot.swift) consumes.
"""

import json

from ares.models.cognitive import (
    SCHEMA_VERSION,
    CognitiveSnapshot,
    LoopBlock,
    ThoughtBlock,
)


def test_default_snapshot_is_idle():
    snap = CognitiveSnapshot()
    assert snap.schema_version == SCHEMA_VERSION
    assert snap.running is False
    assert snap.loop.cycle == 0
    assert snap.loop.phase == "idle"
    assert snap.loop.urgency == "low"
    assert snap.loop.budget_remaining == 1.0
    assert snap.thought is None
    assert snap.errors == []
    assert snap.timestamp > 0


def test_json_round_trip_preserves_shape():
    original = CognitiveSnapshot(
        running=True,
        loop=LoopBlock(
            cycle=3,
            phase="think",
            urgency="medium",
            budget_remaining=0.6,
            tokens_used=12_345,
            elapsed_ms=2_100,
        ),
        thought=ThoughtBlock(summary="drafting response", depth=2),
        errors=["transient bus warning"],
    )
    payload = original.model_dump_json()
    decoded = CognitiveSnapshot.model_validate_json(payload)
    assert decoded == original


def test_serialized_keys_use_snake_case():
    """The Swift client decodes via snake_case keys — guard that here."""
    snap = CognitiveSnapshot()
    encoded = json.loads(snap.model_dump_json())
    assert "schema_version" in encoded
    assert "budget_remaining" in encoded["loop"]
    assert "tokens_used" in encoded["loop"]
    assert "elapsed_ms" in encoded["loop"]


def test_extra_fields_on_decode_are_ignored():
    """Adding new keys server-side must remain non-breaking for older clients."""
    payload = {
        "schema_version": SCHEMA_VERSION,
        "timestamp": 1.0,
        "running": False,
        "loop": {
            "cycle": 0,
            "phase": "idle",
            "urgency": "low",
            "budget_remaining": 1.0,
            "tokens_used": 0,
            "elapsed_ms": 0,
            "future_metric": "ignored",  # unknown nested field
        },
        "thought": None,
        "errors": [],
        "future_top_level": "ignored",  # unknown top-level field
    }
    snap = CognitiveSnapshot.model_validate(payload)
    assert snap.loop.cycle == 0
