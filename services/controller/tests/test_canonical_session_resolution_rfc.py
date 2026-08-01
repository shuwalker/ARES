from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHITECTURE = ROOT.parents[1] / "docs" / "ARCHITECTURE.md"


def test_canonical_session_resolution_contract_is_canonicalized():
    assert ARCHITECTURE.exists(), "canonical architecture document must exist"
    assert "Canonical Session Resolution" in ARCHITECTURE.read_text(encoding="utf-8")


def test_canonical_session_resolution_contract_names_entrypoints_and_outputs():
    text = ARCHITECTURE.read_text(encoding="utf-8")

    required_terms = [
        "URL route",
        "query parameter",
        "localStorage",
        "sidebar",
        "pre_compression_snapshot",
        "canonical_visible_session_id",
        "continuation_session_id",
        "parent_session_id",
        "direct session open",
        "browser boot restore",
    ]

    missing = [term for term in required_terms if term not in text]
    assert missing == []
