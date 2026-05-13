"""Idle reflexion — what ARES does between exchanges.

Runs as a background pass that consolidates episodics into summary facts,
deduplicates near-identical facts, and surfaces unresolved questions for
future cycles. Heuristic for v1 — the API is stable, the implementation
can sharpen as real embedders come online.

Three handlers, one orchestrator:

  * `consolidate_episodics` — groups recent episodics by session and
    writes a "session X had N exchanges about <topic>" summary fact.
  * `dedupe_facts` — collapses semantic facts that say almost the same
    thing.
  * `surface_open_questions` — scans episodics for questions that didn't
    get answered in a subsequent exchange.

Each handler takes a `MemoryStore` and returns a small report. The
orchestrator `run_idle_pass` calls all three and returns a combined
`IdleReport`. Schedulers (cron, asyncio interval, manual `/api/idle/run`)
plug in on top.
"""

from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

from ares.memory_store import Embedder, MemoryStore, _cosine


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------


@dataclass
class IdleReport:
    consolidated_sessions: int = 0
    summary_fact_ids: list[str] = field(default_factory=list)
    duplicates_merged: int = 0
    open_questions: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "consolidated_sessions": self.consolidated_sessions,
            "summary_fact_ids": list(self.summary_fact_ids),
            "duplicates_merged": self.duplicates_merged,
            "open_questions": list(self.open_questions),
        }


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------


def consolidate_episodics(
    memory: MemoryStore,
    max_episodics: int = 40,
) -> tuple[int, list[str]]:
    """Group recent episodics by session_id metadata and write one summary
    fact per session.

    Returns `(sessions_consolidated, summary_fact_ids)`. Idempotent at the
    fact level: re-running creates new summaries but never modifies prior
    ones, so callers can decide on retention policy.
    """
    items = memory.list_episodics(limit=max_episodics)
    if not items:
        return 0, []

    by_session: dict[str, list[dict]] = defaultdict(list)
    for it in items:
        sid = (it.get("metadata") or {}).get("session_id")
        if sid:
            by_session[sid].append(it)

    fact_ids: list[str] = []
    consolidated = 0
    for sid, entries in by_session.items():
        # Single-entry sessions are too thin to summarize.
        if len(entries) < 2:
            continue
        # Pick the most recent episodic in the session as the provenance.
        source = entries[0]["id"]  # list_episodics returns newest-first
        topic = _derive_topic([e["text"] for e in entries])
        summary = f"session {sid[:8]}: {len(entries)} exchanges about {topic}"
        fid = memory.add_fact(
            subject=f"session:{sid}",
            predicate="summarized_as",
            obj=summary,
            source_episodic_id=source,
        )
        fact_ids.append(fid)
        consolidated += 1

    return consolidated, fact_ids


def dedupe_facts(
    memory: MemoryStore,
    embedder: Optional[Embedder] = None,
    threshold: float = 0.95,
    limit: int = 200,
) -> int:
    """Delete near-duplicate semantic facts.

    Pairwise cosine on fact text; collapses everything above `threshold`,
    keeping the older entry (lower `created_at`). Returns the number of
    facts deleted.

    Pure-Python O(n²) — fine for the personal-scale fact store. Larger
    stores should swap in a real backend with batch similarity.
    """
    embedder = embedder or memory.embedder
    facts = memory.list_facts(limit=limit)
    if len(facts) < 2:
        return 0

    # Embed once per fact.
    vectors = [(f, embedder.embed(_fact_text(f))) for f in facts]
    # Sort oldest-first so we keep the original and drop later duplicates.
    vectors.sort(key=lambda pair: pair[0].created_at)

    deleted: set[str] = set()
    for i in range(len(vectors)):
        if vectors[i][0].id in deleted:
            continue
        keeper, kvec = vectors[i]
        for j in range(i + 1, len(vectors)):
            cand, cvec = vectors[j]
            if cand.id in deleted:
                continue
            if _cosine(kvec, cvec) >= threshold:
                memory.delete_fact(cand.id)
                deleted.add(cand.id)

    return len(deleted)


def surface_open_questions(
    memory: MemoryStore,
    max_episodics: int = 60,
) -> list[str]:
    """Return the text of recent questions that lack a follow-up answer
    in a later episodic from the same session.

    Heuristic for v1 — a question is any episodic text containing "?",
    "should" or "need to". An "answer" is any later episodic from the
    same session. Good enough to populate a "things ARES is still
    thinking about" surface.
    """
    items = memory.list_episodics(limit=max_episodics)
    # list_episodics returns newest-first; we want oldest-first for
    # "is there a later follow-up?" logic.
    items = list(reversed(items))

    by_session_after: dict[str, list[int]] = defaultdict(list)
    for i, it in enumerate(items):
        sid = (it.get("metadata") or {}).get("session_id") or ""
        by_session_after[sid].append(i)

    open_questions: list[str] = []
    for i, it in enumerate(items):
        text = it.get("text") or ""
        if not _looks_like_open_thread(text):
            continue
        sid = (it.get("metadata") or {}).get("session_id") or ""
        later_indices = [j for j in by_session_after[sid] if j > i]
        if not later_indices:
            open_questions.append(_first_sentence(text))

    # Deduplicate while preserving order.
    seen: set[str] = set()
    result: list[str] = []
    for q in open_questions:
        if q not in seen:
            seen.add(q)
            result.append(q)
    return result


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------


def run_idle_pass(
    memory: MemoryStore,
    embedder: Optional[Embedder] = None,
    consolidate_max: int = 40,
    dedupe_threshold: float = 0.95,
    questions_max: int = 60,
) -> IdleReport:
    """Run all three idle handlers and return a combined report."""
    consolidated, fact_ids = consolidate_episodics(memory, max_episodics=consolidate_max)
    merged = dedupe_facts(memory, embedder=embedder, threshold=dedupe_threshold)
    questions = surface_open_questions(memory, max_episodics=questions_max)
    return IdleReport(
        consolidated_sessions=consolidated,
        summary_fact_ids=fact_ids,
        duplicates_merged=merged,
        open_questions=questions,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_OPEN_RE = re.compile(r"(\?|\bshould\b|\bneed to\b|\btodo\b)", re.IGNORECASE)


def _looks_like_open_thread(text: str) -> bool:
    return bool(_OPEN_RE.search(text))


def _first_sentence(text: str) -> str:
    # Strip the "USER: " / "ARES: " prefixes that chat episodics use.
    cleaned = re.sub(r"^(USER|ARES):\s*", "", text.strip(), flags=re.IGNORECASE | re.MULTILINE)
    parts = re.split(r"(?<=[.?!])\s+", cleaned.strip(), maxsplit=1)
    return parts[0][:240] if parts else cleaned[:240]


def _derive_topic(texts: list[str]) -> str:
    """Pick a short topic phrase from a cluster of episodics.

    v1 heuristic: longest token (>=4 chars) that appears in the majority
    of texts, falling back to the first non-trivial token of the most
    recent entry. Real embeddings unlock real clustering later.
    """
    if not texts:
        return "unknown"
    word_counts: dict[str, int] = defaultdict(int)
    for text in texts:
        tokens = {t.lower() for t in re.findall(r"[A-Za-z]{4,}", text)}
        for t in tokens:
            word_counts[t] += 1
    if word_counts:
        most_common = max(word_counts.items(), key=lambda kv: (kv[1], len(kv[0])))
        if most_common[1] >= max(2, len(texts) // 2):
            return most_common[0]
    # Fallback: first long token in the most recent text.
    tokens = re.findall(r"[A-Za-z]{4,}", texts[0])
    return (tokens[0] if tokens else "unknown").lower()


def _fact_text(fact) -> str:
    return f"{fact.subject} {fact.predicate} {fact.object}"
