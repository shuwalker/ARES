"""ARES IPC server.

Binds a ZeroMQ ROUTER socket to a Unix domain socket (configurable via
AresConfig.ipc.socket_path, default `/tmp/ares_ipc.sock`) and routes
incoming Envelope protobuf messages to per-payload handlers.

Handlers are registered with the @server.handler(message_type) decorator
where message_type is the Envelope.WhichOneof("payload") string —
"log_trace", "approval_request", "approval_response", "state_change",
or "config_update".

Replies (if any) are sent back to the original DEALER identity by
returning an Envelope from the handler.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable, Optional

import zmq
import zmq.asyncio

from ares.ipc import ares_pb2

logger = logging.getLogger("ares.ipc")


Handler = Callable[["ares_pb2.Envelope"], Awaitable[Optional["ares_pb2.Envelope"]]]


class IPCServer:
    """Async ROUTER-side IPC server."""

    def __init__(self, socket_path: str) -> None:
        self.socket_path = socket_path
        self.endpoint = f"ipc://{socket_path}"
        self._ctx = zmq.asyncio.Context.instance()
        self._sock: Optional[zmq.asyncio.Socket] = None
        self._handlers: dict[str, Handler] = {}
        self._stop = asyncio.Event()

    def handler(self, payload_field: str) -> Callable[[Handler], Handler]:
        """Register a coroutine to handle a payload variant."""

        def _wrap(fn: Handler) -> Handler:
            self._handlers[payload_field] = fn
            return fn

        return _wrap

    async def run(self) -> None:
        self._sock = self._ctx.socket(zmq.ROUTER)
        self._sock.bind(self.endpoint)
        logger.info("IPC server bound to %s", self.endpoint)

        try:
            while not self._stop.is_set():
                try:
                    frames = await asyncio.wait_for(
                        self._sock.recv_multipart(),
                        timeout=0.5,
                    )
                except asyncio.TimeoutError:
                    continue
                if len(frames) < 2:
                    logger.warning("dropped malformed ROUTER frame: %r", frames)
                    continue
                identity, payload = frames[0], frames[-1]
                await self._dispatch(identity, payload)
        finally:
            self._sock.close(linger=0)
            self._sock = None

    async def stop(self) -> None:
        self._stop.set()

    async def _dispatch(self, identity: bytes, payload: bytes) -> None:
        env = ares_pb2.Envelope()
        try:
            env.ParseFromString(payload)
        except Exception as e:
            logger.warning("malformed Envelope from %r: %s", identity, e)
            return

        which = env.WhichOneof("payload")
        if which is None:
            logger.debug("empty Envelope from %r", identity)
            return

        fn = self._handlers.get(which)
        if fn is None:
            logger.debug("no handler for payload %r", which)
            return

        try:
            reply = await fn(env)
        except Exception:
            logger.exception("handler %s raised", which)
            return

        if reply is not None and self._sock is not None:
            await self._sock.send_multipart([identity, b"", reply.SerializeToString()])


def build_server() -> IPCServer:
    """Construct an IPCServer from the active AresConfig."""
    from ares.runtime.config import get_config

    return IPCServer(get_config().ipc.socket_path)
