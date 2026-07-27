"""Dependency-free markdown chunking for the Context Store.

Local Profile / project-context files (MEMORY.md, AGENTS.md, etc.) are bounded
by PROJECT_CONTEXT_MAX_BYTES (20KB, see api/memory_store.py) — this is not
corpus-scale RAG, so a small heading/paragraph splitter is sufficient and a
chunking library is not warranted.
"""

from __future__ import annotations

from dataclasses import dataclass
import re

_HEADING_RE = re.compile(r"^#{1,6}\s+.*$", re.MULTILINE)


@dataclass(frozen=True)
class TextChunk:
    text: str
    index: int
    heading: str


def _split_paragraphs(block: str) -> list[str]:
    return [part.strip() for part in re.split(r"\n\s*\n", block) if part.strip()]


def _split_sections(text: str) -> list[tuple[str, str]]:
    """Split text into (heading, body) pairs. Content before the first heading
    gets an empty heading."""
    matches = list(_HEADING_RE.finditer(text))
    if not matches:
        return [("", text)]
    sections: list[tuple[str, str]] = []
    if matches[0].start() > 0:
        sections.append(("", text[: matches[0].start()]))
    for index, match in enumerate(matches):
        heading = match.group().strip()
        body_start = match.end()
        body_end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections.append((heading, text[body_start:body_end]))
    return sections


def chunk_markdown(text: str, *, max_chars: int = 1200, overlap_chars: int = 150) -> list[TextChunk]:
    """Chunk markdown on heading/paragraph boundaries, preserving heading context.

    A heading is never separated from its first paragraph. Chunks that would
    exceed max_chars start a new chunk, carrying up to overlap_chars of
    trailing text (or the last full paragraph, whichever is smaller) forward
    for continuity.
    """
    if not text or not text.strip():
        return []

    chunks: list[TextChunk] = []
    index = 0

    for heading, body in _split_sections(text):
        paragraphs = _split_paragraphs(body)
        if not paragraphs:
            if heading:
                chunks.append(TextChunk(text=heading, index=index, heading=heading))
                index += 1
            continue

        current = heading
        carry = ""
        for paragraph in paragraphs:
            candidate = f"{current}\n\n{paragraph}" if current else paragraph
            if current and current != heading and len(candidate) > max_chars:
                chunks.append(TextChunk(text=current, index=index, heading=heading))
                index += 1
                last_paragraph = current.split("\n\n")[-1]
                carry = last_paragraph[-overlap_chars:] if len(last_paragraph) > overlap_chars else last_paragraph
                current = f"{heading}\n\n{carry}\n\n{paragraph}" if heading else f"{carry}\n\n{paragraph}"
            else:
                current = candidate
        if current:
            chunks.append(TextChunk(text=current, index=index, heading=heading))
            index += 1

    return chunks
