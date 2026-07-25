"""Pure unit tests for api.context_chunker.chunk_markdown() -- no I/O."""
from __future__ import annotations

from api.context_chunker import chunk_markdown


def test_empty_input_returns_no_chunks():
    assert chunk_markdown("") == []
    assert chunk_markdown("   \n  ") == []


def test_single_paragraph_no_heading():
    chunks = chunk_markdown("just a paragraph\n\nanother paragraph")
    assert len(chunks) == 1
    assert chunks[0].heading == ""
    assert "just a paragraph" in chunks[0].text
    assert "another paragraph" in chunks[0].text


def test_heading_boundaries_preserved():
    text = "# Heading One\n\nParagraph one.\n\n## Heading Two\n\nParagraph two."
    chunks = chunk_markdown(text)
    headings = [c.heading for c in chunks]
    assert "# Heading One" in headings
    assert "## Heading Two" in headings
    # Each heading stays attached to its own paragraph, never merged together.
    one = next(c for c in chunks if c.heading == "# Heading One")
    two = next(c for c in chunks if c.heading == "## Heading Two")
    assert "Paragraph one." in one.text
    assert "Paragraph two." not in one.text
    assert "Paragraph two." in two.text


def test_heading_never_separated_from_first_paragraph():
    text = "# H\n\nFirst paragraph right after heading."
    chunks = chunk_markdown(text, max_chars=10)  # tiny budget, would force a split if not protected
    assert chunks[0].text.startswith("# H")
    assert "First paragraph" in chunks[0].text


def test_respects_max_chars_and_produces_multiple_chunks():
    body = "\n\n".join(f"Paragraph number {i} with some filler words to pad it out nicely." for i in range(10))
    text = "# H\n\n" + body
    chunks = chunk_markdown(text, max_chars=150, overlap_chars=30)
    assert len(chunks) > 1
    for chunk in chunks:
        # Allow some slack: the heading + overlap prefix can push slightly over.
        assert len(chunk.text) <= 250


def test_overlap_present_between_consecutive_chunks():
    body = "\n\n".join(f"Paragraph number {i} with some filler words to pad it out nicely." for i in range(6))
    chunks = chunk_markdown("# H\n\n" + body, max_chars=150, overlap_chars=30)
    assert len(chunks) >= 2
    # The tail of one chunk should reappear at the start of the next (the carried overlap).
    first_tail = chunks[0].text[-20:]
    assert any(first_tail[-10:] in chunk.text for chunk in chunks[1:])


def test_content_before_first_heading_gets_empty_heading():
    text = "intro paragraph\n\n# First Heading\n\nbody text"
    chunks = chunk_markdown(text)
    assert chunks[0].heading == ""
    assert "intro paragraph" in chunks[0].text


def test_chunk_index_is_sequential():
    text = "# A\n\npara a\n\n# B\n\npara b\n\n# C\n\npara c"
    chunks = chunk_markdown(text)
    assert [c.index for c in chunks] == list(range(len(chunks)))
