"""Base class for Web Automation Reverse APIs via safari-mcp."""

from __future__ import annotations

from typing import Any, Dict, List

from .base import AgenticBackend


class ReverseAPIBase(AgenticBackend):
    """
    Base class for Reverse API web-scraping backends.
    
    Relies on `safari-mcp` (https://github.com/achiya-automation/safari-mcp) 
    to automate the user's local, logged-in Safari browser.
    """
    supports_tools = False
    supports_persona = False
    supports_hybrid = False

    def is_available(self) -> bool:
        # We assume safari-mcp is available if npx is installed. 
        # For this scaffolding, we simply return True.
        import shutil
        return shutil.which("npx") is not None

    def get_worker_target(self) -> tuple:
        """Return the target for the reverse API worker."""
        # The worker function is defined inside the subclass.
        return self._run_web_scraping_worker, False, False

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        return {
            "available": available,
            "label": f"{self.get_backend_name()} (Web)",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
                "supports_hybrid": self.supports_hybrid,
            }
        }

    def _get_safari_mcp_client(self):
        """
        Returns an active MCP client connected to `npx safari-mcp`.
        This is a placeholder for your local AI to implement using 
        the standard MCP Python SDK.
        """
        # LOCAL AI TODO: Implement MCP client connection here.
        # Example:
        # from mcp import ClientSession, StdioServerParameters
        # from mcp.client.stdio import stdio_client
        # server_params = StdioServerParameters(command="npx", args=["safari-mcp"])
        # ...
        raise NotImplementedError("MCP client logic must be implemented by local AI.")

    def _run_web_scraping_worker(self, session_id: str, message: str, model: str, **kwargs):
        """
        The actual worker that routes to the specific web scraper.
        """
        # We execute the run_turn logic which the specific adapter will implement.
        result = self.run_turn(message, session_id, **kwargs)
        
        # ARES streaming protocol expects SSE events. For simplicity in scaffolding,
        # we will just mock a single block response. 
        # LOCAL AI TODO: Implement proper SSE token streaming.
        pass

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        raise NotImplementedError("Subclasses must implement run_turn()")
