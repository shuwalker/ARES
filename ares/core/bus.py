"""ARES Bus — ZMQ pub/sub backbone connecting face, voice, vision, and robot modules.

Based on Lilith's ZMQ bus architecture, adapted for ARES with:
- Named channels with typed messages
- Topic-based subscription filtering
- Health check / heartbeat system
- Thread-safe message dispatch
- Graceful shutdown

The bus is the single nervous system of ARES. Every module (face, voice,
vision, robot, MCP bridge) connects to the bus as either a publisher or
subscriber. The brain (Hermes) publishes responses; face modules subscribe
and render.

Ports:
    5570  AUDIO_RAW      Mic audio chunks → STT
    5571  STT_TEXT       Transcribed text → brain
    5572  BRAIN_OUTPUT   Brain responses → all consumers (PUB/SUB)
    5573  FACE_STATE     Face state updates → face renderer
    5574  ROBOT_CMD      Robot motor/behavior commands
    5575  TTS_CONTROL     TTS commands → speech synthesis
    5576  HEALTH          Heartbeat / status monitoring
    5577  VISION          Vision module events
    5578  MCP_BRIDGE      MCP ↔ bus bridge events

Usage:
    from ares.core.bus import ARESBus, get_bus

    bus = get_bus()  # Singleton

    # Subscribe to brain output
    sub = bus.subscribe("brain_output")
    while running:
        msg = sub.receive(timeout_ms=1000)
        if msg:
            print(msg)

    # Publish a face state update
    pub = bus.publisher("face_state")
    pub.send({"state": "thinking", "color": [0.2, 0.6, 1.0]})
"""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger("ares.bus")

# ---------------------------------------------------------------------------
# Port map — named channels with default ports
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PortMap:
    """ZMQ port assignments for ARES bus channels.

    Each channel is a TCP port on localhost. PUB sockets bind;
    SUB/PUSH/PULL sockets connect.
    """

    AUDIO_RAW: int = 5570  # Mic audio chunks → STT
    STT_TEXT: int = 5571  # Transcribed text → brain
    BRAIN_OUTPUT: int = 5572  # Brain responses → all consumers (PUB/SUB)
    FACE_STATE: int = 5573  # Face state updates → face renderer
    ROBOT_CMD: int = 5574  # Robot motor/behavior commands
    TTS_CONTROL: int = 5575  # TTS commands → speech synthesis
    HEALTH: int = 5576  # Heartbeat / status monitoring
    VISION: int = 5577  # Vision module events
    MCP_BRIDGE: int = 5578  # MCP ↔ bus bridge events


DEFAULT_PORTS = PortMap()


def get_address(port: int, host: str = "127.0.0.1") -> str:
    """Return a TCP connection string for the given port."""
    return f"tcp://{host}:{port}"


# ---------------------------------------------------------------------------
# Message types
# ---------------------------------------------------------------------------


@dataclass
class BusMessage:
    """A typed message on the ARES bus.

    Every message has a type (for topic filtering), a source (which module
    sent it), a timestamp, and a payload dict.
    """

    type: str  # e.g. "face_state", "stt_text", "brain_response"
    source: str  # e.g. "hermes", "whisper", "face_renderer"
    payload: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    msg_id: str = ""

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "source": self.source,
            "payload": self.payload,
            "timestamp": self.timestamp,
            "msg_id": self.msg_id,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "BusMessage":
        return cls(
            type=data.get("type", ""),
            source=data.get("source", ""),
            payload=data.get("payload", {}),
            timestamp=data.get("timestamp", time.time()),
            msg_id=data.get("msg_id", ""),
        )

    def to_json(self) -> str:
        return json.dumps(self.to_dict())

    @classmethod
    def from_json(cls, raw: str) -> "BusMessage":
        return cls.from_dict(json.loads(raw))


# ---------------------------------------------------------------------------
# Channel — a bind/connect wrapper around a ZMQ socket
# ---------------------------------------------------------------------------


class Channel:
    """A named communication channel on the bus.

    Wraps a ZMQ socket with send/receive and automatic serialization.
    Thread-safe for sends (ZMQ sockets are NOT thread-safe for concurrent
    send+receive — use separate sockets for that pattern).
    """

    def __init__(self, name: str, socket, lock: threading.Lock = None):
        self.name = name
        self._socket = socket
        self._lock = lock or threading.Lock()

    def send(self, data: Dict[str, Any]) -> None:
        """Send a dict as JSON over the channel."""
        with self._lock:
            self._socket.send_json(data)

    def send_message(self, msg: BusMessage) -> None:
        """Send a BusMessage over the channel."""
        self.send(msg.to_dict())

    def receive(self, timeout_ms: int = 100) -> Optional[Dict[str, Any]]:
        """Non-blocking receive with timeout. Returns dict or None."""
        try:
            import zmq

            poller = zmq.Poller()
            poller.register(self._socket, zmq.POLLIN)
            events = dict(poller.poll(timeout_ms))
            if self._socket in events:
                return self._socket.recv_json()
        except ImportError:
            logger.warning("zmq not installed — cannot receive on bus")
        except Exception as e:
            logger.debug("Bus receive error: %s", e)
        return None

    def receive_message(self, timeout_ms: int = 100) -> Optional[BusMessage]:
        """Non-blocking receive, returns BusMessage or None."""
        data = self.receive(timeout_ms)
        if data:
            return BusMessage.from_dict(data)
        return None

    def close(self) -> None:
        """Close the underlying socket."""
        try:
            self._socket.close(linger=0)
        except Exception as e:
            logger.warning("Bus socket close error: %s", e)


# ---------------------------------------------------------------------------
# ARESBus — the main bus class
# ---------------------------------------------------------------------------


class ARESBus:
    """ZMQ pub/sub backbone for ARES modules.

    The bus is a singleton. Get it with get_bus().

    Publishers bind to TCP ports. Subscribers connect to them.
    All messages are JSON with a "type" field used for topic filtering.

    Architecture:

        [Hermes Brain] --PUB--> :5572 (BRAIN_OUTPUT)
                                    |
                            +-------+-------+-------+
                            |       |       |       |
                        [Face]  [Voice] [Robot] [MCP]

        [Whisper STT] --PUSH--> :5571 (STT_TEXT)

        [Face Renderer] --SUB--> :5573 (FACE_STATE)

        [Mic] --PUSH--> :5570 (AUDIO_RAW)
    """

    def __init__(self, ports: PortMap = None, host: str = "127.0.0.1"):
        self.ports = ports or DEFAULT_PORTS
        self.host = host
        self._channels: Dict[str, Channel] = {}
        self._context = None
        self._owns_context = False
        self._running = False
        self._heartbeat_thread: Optional[threading.Thread] = None
        self._listeners: Dict[str, List[Callable]] = {}
        self._lock = threading.Lock()
        self._zmq_available = False

        try:
            import zmq  # noqa: F401 — availability probe

            self._zmq_available = True
        except ImportError:
            logger.warning("zmq not installed — bus will use in-process dispatch only")

    def _ensure_context(self):
        """Lazily create ZMQ context."""
        if self._context is None and self._zmq_available:
            import zmq

            self._context = zmq.Context()
            self._owns_context = True

    # -- Publisher (binds to port, broadcasts to subscribers) ---------------

    def publisher(self, channel_name: str) -> Channel:
        """Create a PUB socket that binds to the channel's port.

        Only one publisher should bind per channel. Call this from the
        module that OWNS the channel (e.g., the brain for BRAIN_OUTPUT).
        """
        if not self._zmq_available:
            return Channel(channel_name, _StubSocket())

        import zmq

        self._ensure_context()

        port = getattr(self.ports, channel_name.upper(), None)
        if port is None:
            raise ValueError(
                f"Unknown channel: {channel_name}. " f"Valid: {[f.lower() for f in self.ports.__dataclass_fields__]}"
            )

        sock = self._context.socket(zmq.PUB)
        sock.bind(get_address(port, self.host))
        channel = Channel(channel_name, sock, self._lock)
        self._channels[channel_name] = channel
        return channel

    # -- Subscriber (connects to port, receives broadcasts) -----------------

    def subscribe(self, channel_name: str, topic: str = "") -> Channel:
        """Create a SUB socket that connects to the channel's port.

        Optionally filter by topic prefix (e.g., "face_state" to only
        receive face state updates from the BRAIN_OUTPUT channel).
        """
        if not self._zmq_available:
            return Channel(channel_name, _StubSocket())

        import zmq

        self._ensure_context()

        port = getattr(self.ports, channel_name.upper(), None)
        if port is None:
            raise ValueError(
                f"Unknown channel: {channel_name}. " f"Valid: {[f.lower() for f in self.ports.__dataclass_fields__]}"
            )

        sock = self._context.socket(zmq.SUB)
        sock.connect(get_address(port, self.host))
        sock.setsockopt(zmq.SUBSCRIBE, topic.encode("utf-8") if topic else b"")
        channel = Channel(channel_name, sock)
        self._channels[f"{channel_name}_sub_{id(sock)}"] = channel
        return channel

    # -- Push/Pull (point-to-point channels) --------------------------------

    def push(self, channel_name: str) -> Channel:
        """Create a PUSH socket that connects to the channel's port.

        Use for point-to-point communication (e.g., mic audio to STT).
        """
        if not self._zmq_available:
            return Channel(channel_name, _StubSocket())

        import zmq

        self._ensure_context()

        port = getattr(self.ports, channel_name.upper(), None)
        if port is None:
            raise ValueError(f"Unknown channel: {channel_name}")

        sock = self._context.socket(zmq.PUSH)
        sock.connect(get_address(port, self.host))
        channel = Channel(channel_name, sock, self._lock)
        self._channels[channel_name] = channel
        return channel

    def pull(self, channel_name: str) -> Channel:
        """Create a PULL socket that binds to the channel's port.

        Use for point-to-point communication (e.g., STT receiving audio).
        """
        if not self._zmq_available:
            return Channel(channel_name, _StubSocket())

        import zmq

        self._ensure_context()

        port = getattr(self.ports, channel_name.upper(), None)
        if port is None:
            raise ValueError(f"Unknown channel: {channel_name}")

        sock = self._context.socket(zmq.PULL)
        sock.bind(get_address(port, self.host))
        channel = Channel(channel_name, sock)
        self._channels[channel_name] = channel
        return channel

    # -- In-process listener dispatch (no ZMQ needed) -----------------------

    def on(self, event_type: str, callback: Callable[[BusMessage], None]) -> None:
        """Register a callback for in-process event dispatch.

        Works without ZMQ — just calls the callback directly when
        a matching event is dispatched.
        """
        with self._lock:
            if event_type not in self._listeners:
                self._listeners[event_type] = []
            self._listeners[event_type].append(callback)

    def off(self, event_type: str, callback: Callable[[BusMessage], None]) -> None:
        """Remove a callback."""
        with self._lock:
            if event_type in self._listeners:
                self._listeners[event_type] = [cb for cb in self._listeners[event_type] if cb != callback]

    def dispatch(self, msg: BusMessage) -> None:
        """Dispatch a message to in-process listeners (no ZMQ).

        This is the in-process alternative to ZMQ publishing —
        useful for single-process mode or testing.
        """
        with self._lock:
            callbacks = self._listeners.get(msg.type, []) + self._listeners.get("*", [])

        for callback in callbacks:
            try:
                callback(msg)
            except Exception as e:
                logger.warning("Listener error on %s: %s", msg.type, e)

    # -- Health / heartbeat -------------------------------------------------

    def start_heartbeat(self, interval_sec: float = 5.0, source: str = "bus") -> None:
        """Start publishing heartbeat messages on the HEALTH channel."""
        self._running = True

        def _heartbeat():
            if self._zmq_available:
                try:
                    pub = self.publisher("health")
                except Exception:
                    return
            while self._running:
                msg = BusMessage(
                    type="heartbeat",
                    source=source,
                    payload={"status": "alive", "uptime": time.time()},
                )
                if self._zmq_available:
                    try:
                        pub.send_message(msg)
                    except Exception as e:
                        logger.debug("Heartbeat publish error: %s", e)
                self.dispatch(msg)
                time.sleep(interval_sec)

        self._heartbeat_thread = threading.Thread(target=_heartbeat, daemon=True)
        self._heartbeat_thread.start()

    def stop(self) -> None:
        """Shut down the bus — close all sockets and context."""
        self._running = False
        for channel in self._channels.values():
            channel.close()
        self._channels.clear()
        if self._owns_context and self._context:
            self._context.destroy(linger=0)
            self._context = None

    # -- Status -------------------------------------------------------------

    def status(self) -> dict:
        """Return bus status for health checks."""
        return {
            "running": self._running,
            "zmq_available": self._zmq_available,
            "channels": list(self._channels.keys()),
            "host": self.host,
            "ports": {f.lower(): getattr(self.ports, f.lower(), None) for f in self.ports.__dataclass_fields__},
            "listeners": {k: len(v) for k, v in self._listeners.items()},
        }


# ---------------------------------------------------------------------------
# Stub socket for when ZMQ is not installed
# ---------------------------------------------------------------------------


class _StubSocket:
    """No-op socket replacement when zmq is not installed.

    Allows the bus to work in in-process dispatch mode without ZMQ.
    All send/receive calls become no-ops; only dispatch() works.
    """

    def send_json(self, data):
        pass

    def recv_json(self):
        return None

    def close(self, linger=0):
        pass

    def setsockopt(self, *args):
        pass


# ---------------------------------------------------------------------------
# Singleton bus instance
# ---------------------------------------------------------------------------

_BUS_INSTANCE: Optional[ARESBus] = None
_BUS_LOCK = threading.Lock()


def get_bus(ports: PortMap = None, host: str = "127.0.0.1") -> ARESBus:
    """Get the singleton ARES bus instance.

    Creates the bus on first call. Subsequent calls return the same instance.
    """
    global _BUS_INSTANCE
    with _BUS_LOCK:
        if _BUS_INSTANCE is None:
            _BUS_INSTANCE = ARESBus(ports=ports, host=host)
        return _BUS_INSTANCE


def reset_bus() -> None:
    """Reset the singleton bus (for testing)."""
    global _BUS_INSTANCE
    with _BUS_LOCK:
        if _BUS_INSTANCE is not None:
            _BUS_INSTANCE.stop()
        _BUS_INSTANCE = None
