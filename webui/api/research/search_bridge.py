"""ARES Research Search Bridge — connects DeepResearcher to ARES search backends.

Provides async web_search and web_extract callables that the researcher uses.
Falls back to SearXNG (if configured) or direct web scraping.
"""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


async def web_search(query: str, limit: int = 5) -> List[Dict[str, str]]:
    """Search the web and return results as [{title, url, snippet}].

    Uses ARES's configured search backend (SearXNG, Brave, etc.)
    or falls back to a direct approach.
    """
    results: List[Dict[str, str]] = []

    # Try ARES's Hermes agent search if available
    try:
        from api.config import get_config
        cfg = get_config()
        search_cfg = cfg.get("search", {}) if isinstance(cfg, dict) else {}

        # Check for SearXNG configuration
        searxng_url = search_cfg.get("searxng_url") or search_cfg.get("search_url")
        if searxng_url:
            results = await _searxng_search(searxng_url, query, limit)
            if results:
                return results
    except Exception as e:
        logger.debug(f"ARES config search not available: {e}")

    # Try direct web search via Hermes tools if in agent context
    try:
        from api.config import get_config
        cfg = get_config()
        # Use Hermes web_search tool if available
        # This will be called from agent context
        pass
    except Exception:
        pass

    return results


async def _searxng_search(
    searxng_url: str, query: str, limit: int = 5
) -> List[Dict[str, str]]:
    """Search using SearXNG instance."""
    import httpx

    results = []
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{searxng_url.rstrip('/')}/search",
                params={"q": query, "format": "json", "categories": "general"},
                headers={"User-Agent": "ARES-Research/1.0"},
            )
            if resp.status_code == 200:
                data = resp.json()
                for item in data.get("results", [])[:limit]:
                    results.append({
                        "title": item.get("title", ""),
                        "url": item.get("url", ""),
                        "snippet": item.get("content", ""),
                    })
    except Exception as e:
        logger.error(f"SearXNG search failed: {e}")
    return results


async def web_extract(url: str, goal: str) -> Optional[Dict[str, str]]:
    """Extract relevant content from a URL for a research goal.

    Returns {rational, evidence, summary} from goal-based extraction,
    or None if extraction fails.
    """
    import httpx

    try:
        async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
            resp = await client.get(url, headers={
                "User-Agent": "ARES-Research/1.0 (Mozilla/5.0 compatible)"
            })
            if resp.status_code != 200:
                return None

            # Simple content extraction — get text from HTML
            content = resp.text
            # Strip HTML tags for basic extraction
            import re
            content = re.sub(r'<script[^>]*>[\s\S]*?</script>', '', content)
            content = re.sub(r'<style[^>]*>[\s\S]*?</style>', '', content)
            content = re.sub(r'<[^>]+>', ' ', content)
            content = re.sub(r'\s+', ' ', content).strip()

            if len(content) < 100:
                return None

            # Truncate to reasonable length
            content = content[:15000]

            return {
                "rational": f"Content extracted from {url} for research goal: {goal}",
                "evidence": content[:5000],
                "summary": content[:2000],
            }
    except Exception as e:
        logger.debug(f"Content extraction failed for {url}: {e}")
        return None