"""ARES Research Handler — manages research tasks with persistence and cancellation.

Ported from Odysseus services/research/research_handler.py and
modular-extracts/research/research_handler.py.

Adapted for ARES:
  - Uses ARES research.DeepResearcher instead of Odysseus's
  - Uses ARES session system for persistence
  - Uses ARES config for paths and settings
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path
from typing import Dict, List, Optional

from api.research.deep_researcher import DeepResearcher
from api.research.utils import is_low_quality

logger = logging.getLogger(__name__)

# Default data directory for research results
_DEFAULT_RESEARCH_DIR = Path.home() / ".ares" / "research"


def _research_data_dir() -> Path:
    """Get the ARES research data directory."""
    try:
        from api.config import HOME
        return Path(HOME) / "research"
    except Exception:
        return _DEFAULT_RESEARCH_DIR


class ResearchHandler:
    """Handles research service operations with iterative deep research.

    Manages background tasks, progress callbacks, result persistence,
    and cancellation — the orchestrator around DeepResearcher.
    """

    def __init__(self):
        self._active_tasks: Dict[str, dict] = {}
        data_dir = _research_data_dir()
        data_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # LLM/Search callables — injected by the route layer
    # ------------------------------------------------------------------
    def _make_llm_callable(self, session_id: str = ""):
        """Create an async LLM call function using the ARES backend router."""
        async def llm_call(prompt: str, system: str = "", timeout: int = 120):
            try:
                from api.backends.router import get_router
                from api.config import get_config
                router = get_router(get_config())
                # Use the configured model for research
                response = await router.chat(
                    messages=[{"role": "system", "content": system}] if system else [] +
                              [{"role": "user", "content": prompt}],
                    stream=False,
                )
                return response
            except Exception as e:
                logger.error(f"ARES LLM call failed: {e}")
                return None
        return llm_call

    def _make_search_callable(self):
        """Create an async search function using ARES web search."""
        async def search(query: str):
            try:
                # Use ARES's search integration
                # This will be connected to the configured search backend
                from api.research.search_bridge import web_search
                return await web_search(query)
            except Exception as e:
                logger.error(f"ARES search failed: {e}")
                return []
        return search

    def _make_extract_callable(self):
        """Create an async extract function using ARES web extraction."""
        async def extract(url: str, goal: str):
            try:
                from api.research.search_bridge import web_extract
                return await web_extract(url, goal)
            except Exception as e:
                logger.error(f"ARES extract failed for {url}: {e}")
                return None
        return extract

    # ------------------------------------------------------------------
    # Task registry — background research with persistence
    # ------------------------------------------------------------------

    def start_research(
        self,
        session_id: str,
        query: str,
        max_time: int = 300,
        category: Optional[str] = None,
    ) -> dict:
        """Start research as a background task. Returns task info dict."""
        # Cancel any existing research for this session
        if session_id in self._active_tasks:
            existing = self._active_tasks[session_id]
            if existing.get("status") == "running":
                self.cancel_research(session_id)

        entry: dict = {
            "task": None,
            "researcher": None,
            "query": query,
            "status": "running",
            "progress": {},
            "result": None,
            "started_at": time.time(),
        }
        self._active_tasks[session_id] = entry

        def on_progress(event):
            entry["progress"] = event

        async def _run():
            try:
                researcher = DeepResearcher(
                    llm_call_fn=self._make_llm_callable(session_id),
                    search_fn=self._make_search_callable(),
                    extract_fn=self._make_extract_callable(),
                    max_time=max_time,
                    progress_callback=on_progress,
                    category=category,
                )
                entry["researcher"] = researcher
                result = await researcher.research(query)
                entry["result"] = result
                entry["status"] = "done"
                entry["findings"] = researcher.findings
                entry["analyzed_urls"] = [
                    {"url": u.get("url", ""), "title": u.get("title", "")}
                    for u in researcher.analyzed_urls
                ]
                entry["stats"] = researcher.get_stats()
                self._save_result(session_id, entry)
            except asyncio.CancelledError:
                entry["status"] = "cancelled"
                raise
            except Exception as e:
                logger.error(f"Background research failed: {e}", exc_info=True)
                entry["result"] = str(e)
                entry["status"] = "error"

        task = asyncio.create_task(_run())
        entry["task"] = task
        return {"session_id": session_id, "status": "running", "query": query}

    def get_status(self, session_id: str) -> Optional[dict]:
        """Get current research status for a session."""
        if session_id in self._active_tasks:
            entry = self._active_tasks[session_id]
            return {
                "status": entry["status"],
                "progress": entry["progress"],
                "query": entry["query"],
                "started_at": entry["started_at"],
            }
        # Check disk for completed research
        path = _research_data_dir() / f"{session_id}.json"
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                return {
                    "status": data.get("status", "done"),
                    "progress": {},
                    "query": data.get("query", ""),
                    "started_at": data.get("started_at", 0),
                }
            except Exception:
                pass
        return None

    def cancel_research(self, session_id: str) -> bool:
        """Cancel running research for a session."""
        if session_id not in self._active_tasks:
            return False
        entry = self._active_tasks[session_id]
        if entry["status"] != "running":
            return False
        researcher = entry.get("researcher")
        if researcher:
            researcher.cancel()
        task = entry.get("task")
        if task and not task.done():
            task.cancel()
        entry["status"] = "cancelled"
        return True

    def get_result(self, session_id: str) -> Optional[str]:
        """Get the completed research result."""
        if session_id in self._active_tasks:
            entry = self._active_tasks[session_id]
            if entry["status"] in ("done", "error", "cancelled"):
                return entry.get("result")
        # Check disk
        path = _research_data_dir() / f"{session_id}.json"
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                return data.get("result")
            except Exception:
                pass
        return None

    def get_sources(self, session_id: str) -> Optional[List[dict]]:
        """Get deduplicated source list from research findings."""
        if session_id in self._active_tasks:
            entry = self._active_tasks[session_id]
            if entry.get("sources"):
                return entry["sources"]
            researcher = entry.get("researcher")
            if researcher and researcher.findings:
                return self._extract_sources(researcher.findings)
        # Check disk
        path = _research_data_dir() / f"{session_id}.json"
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                return data.get("sources")
            except Exception:
                pass
        return None

    @staticmethod
    def _extract_sources(findings: list) -> list:
        """Extract deduplicated [{url, title}] from findings."""
        seen = set()
        sources = []
        for f in findings:
            url = f.get("url", "")
            title = f.get("title", "") or url
            summary = f.get("summary", "") or f.get("evidence", "")
            if url and url not in seen and not is_low_quality(summary):
                seen.add(url)
                sources.append({"url": url, "title": title})
        return sources

    def clear_result(self, session_id: str):
        """Remove persisted result after it's been consumed."""
        self._active_tasks.pop(session_id, None)
        path = _research_data_dir() / f"{session_id}.json"
        if path.exists():
            try:
                path.unlink()
            except Exception:
                pass

    def _save_result(self, session_id: str, entry: dict):
        """Persist completed research result to disk."""
        try:
            sources = []
            researcher = entry.get("researcher")
            if researcher and researcher.findings:
                sources = self._extract_sources(researcher.findings)
            entry["sources"] = sources

            path = _research_data_dir() / f"{session_id}.json"
            data = {
                "query": entry["query"],
                "status": entry["status"],
                "result": entry["result"],
                "sources": sources,
                "stats": entry.get("stats", {}),
                "started_at": entry["started_at"],
                "completed_at": time.time(),
            }
            path.write_text(json.dumps(data, indent=2), encoding="utf-8")
            logger.info(f"Research result saved to {path}")
        except Exception as e:
            logger.error(f"Failed to save research result: {e}")