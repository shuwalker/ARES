"""Claude Reverse API Web Scraper Scaffolding."""

from __future__ import annotations

from typing import Any, Dict

from .reverse_api_base import ReverseAPIBase


class ClaudeWebBackend(ReverseAPIBase):
    name = "claude-web"

    def get_backend_name(self) -> str:
        return "Claude (Web Automation)"

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """
        Executes a turn on claude.ai using safari-mcp.

        LOCAL AI TODO:
        1. Initialize `self._get_safari_mcp_client()`.
        2. Use `safari_navigate` to go to https://claude.ai.
        3. Use `safari_type` or `safari_evaluate_javascript` to inject `message` into the textarea.
        4. Use `safari_click` to click the submit button.
        5. Poll `safari_evaluate_javascript` to wait for the generation to finish.
        6. Scrape the final markdown and return it in the format:
           {"text": scraped_text, "error": None, "tool_activity": []}
        """
        raise NotImplementedError("Local AI must implement Claude scraping logic using safari-mcp.")
