"""Adapter inventory catalogs models, transports, gateways, and MCP."""

from __future__ import annotations

from api.backends.catalog import (
    empty_inventory,
    finalize_inventory,
    infer_model_location,
    model_entry,
)
from api.backends.hermes import HermesBackend
from api.backends.jros import JROSBackend


def test_infer_model_location_local_and_cloud():
    assert infer_model_location("ollama", "llama3") == "local"
    assert infer_model_location("ollama-cloud", "deepseek-v4-flash") == "cloud"
    assert infer_model_location("xai", "grok-3") == "cloud"
    assert infer_model_location("local", "gemma.gguf") == "local"


def test_empty_inventory_has_latency_note():
    inv = empty_inventory(worker_id="x", display_name="X")
    assert inv["schema_version"] == 1
    assert "selected_model" in inv["latency"]["depends_on"]
    assert "LLM" in inv["latency"]["note"] or "model" in inv["latency"]["note"].lower()


def test_hermes_inventory_catalogues_cli_and_mcp():
    inv = HermesBackend().inventory()
    inv = finalize_inventory(inv)
    kinds = {t["kind"] for t in inv["transports"]}
    assert "cli" in kinds
    assert "mcp" in kinds
    assert inv["active_execution"]["transport"] == "cli_chat"
    # MCP declared even if ARES is not the client
    assert any(m.get("in_use_by_ares") is False for m in inv["mcp"])
    assert inv["models"], "should list at least one model or placeholder"
    assert any(m.get("location") in {"local", "cloud", "unknown"} for m in inv["models"])


def test_jros_inventory_catalogues_gateway_and_available_models_only():
    inv = JROSBackend().inventory()
    kinds = {t["kind"] for t in inv["transports"]}
    assert "http_gateway" in kinds
    assert inv["active_execution"]["transport"] == "http_gateway"
    # Only real configured models — no fake cloud placeholders
    for m in inv["models"]:
        assert not str(m.get("id") or "").startswith("(")
        assert m.get("location") in {"local", "cloud", "unknown"}


def test_model_entry_shape():
    m = model_entry(id="x", location="cloud", provider="openai", in_use=True)
    assert m["location"] == "cloud"
    assert m["in_use"] is True
