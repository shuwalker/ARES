"""ARES Deep Research — iterative Think→Search→Extract→Synthesize engine.

Ported from Odysseus (pewdiepie-archdaemon/odysseus) deep_research.py and
research_handler.py. Adapted for ARES's architecture:

- Uses ARES adapter/router for LLM calls instead of direct OpenAI-compatible endpoints
- Uses ARES search (web_search) instead of SearXNG
- Uses ARES config/settings instead of Odysseus settings
- Integrates with ARES session system for progress and persistence

License: AGPL-3.0 (matches both projects)
"""

from api.research.deep_researcher import DeepResearcher
from api.research.handler import ResearchHandler

__all__ = ["DeepResearcher", "ResearchHandler"]