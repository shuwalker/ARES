"""Internal HTTP gateway exposing Orchestrator for inter-process communication.

Runs a thin FastAPI server alongside the main application to allow 
separate processes to communicate via the 8080 port.
"""

import asyncio
import logging
from typing import Any, Optional

import uvicorn
from fastapi import FastAPI, BackgroundTasks, Request
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class LocalGateway:
    """Internal HTTP gateway for inter-process module communication."""

    def __init__(
        self,
        orchestrator: Any,
        host: str = "127.0.0.1",
        port: int = 8080,
    ) -> None:
        """Initialize the local gateway.

        Args:
            orchestrator: The main Orchestrator instance.
            host: Interface to bind to.
            port: Port to listen on.
        """
        self.orchestrator = orchestrator
        self.host = host
        self.port = port
        
        self.app = FastAPI(title="ARES Internal Gateway")
        self._setup_routes()
        
        self._server: Optional[uvicorn.Server] = None
        self._task: Optional[asyncio.Task] = None

    def _setup_routes(self) -> None:
        """Configure FastAPI routes."""
        
        @self.app.get("/health")
        async def health_check():
            return {"status": "ok"}
            
        @self.app.post("/execute")
        async def execute_task(request: Request, background_tasks: BackgroundTasks):
            try:
                data = await request.json()
                task_description = data.get("task", "")
                context = data.get("context", {})
                
                if not task_description:
                    return JSONResponse({"error": "Missing 'task' in request body"}, status_code=400)
                
                # We could run this and wait, but often it's better to fire and forget
                # For this implementation, we await it directly as requested:
                # "...that calls orchestrator.execute(task, context)"
                task_record = await self.orchestrator.execute(task_description, context)
                
                return {
                    "task_id": str(task_record.task_id),
                    "status": "accepted"
                }
            except Exception as e:
                logger.error(f"Gateway execute failed: {e}")
                return JSONResponse({"error": str(e)}, status_code=500)

    async def start(self) -> None:
        """Start the uvicorn server in a background task."""
        if self._server:
            return
            
        config = uvicorn.Config(
            app=self.app,
            host=self.host,
            port=self.port,
            log_level="warning",
        )
        self._server = uvicorn.Server(config)
        
        # Start server as a background task so it doesn't block
        self._task = asyncio.create_task(self._server.serve())
        logger.info(f"LocalGateway started at http://{self.host}:{self.port}")

    async def stop(self) -> None:
        """Stop the uvicorn server cleanly."""
        if not self._server:
            return
            
        self._server.should_exit = True
        if self._task:
            try:
                await self._task
            except asyncio.CancelledError:
                pass
                
        self._server = None
        self._task = None
        logger.info("LocalGateway stopped")
