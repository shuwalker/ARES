import zmq
import json
from typing import Optional, Dict, Any

class LilithBus:
    """Manages ZMQ sockets and contexts for inter-plugin communication."""

    def __init__(self, context: Optional[zmq.Context] = None):
        if context is None:
            self.context = zmq.Context()
            self._owns_context = True
        else:
            self.context = context
            self._owns_context = False
            
        self.sockets = []
        
    def _track(self, socket: zmq.Socket) -> zmq.Socket:
        self.sockets.append(socket)
        return socket

    def push_socket(self, address: str) -> zmq.Socket:
        """Connects a PUSH socket (sends workload)."""
        socket = self.context.socket(zmq.PUSH)
        socket.connect(address)
        return self._track(socket)

    def pull_socket(self, address: str) -> zmq.Socket:
        """Binds a PULL socket (receives workload)."""
        socket = self.context.socket(zmq.PULL)
        socket.bind(address)
        return self._track(socket)

    def pub_socket(self, address: str) -> zmq.Socket:
        """Binds a PUB socket (broadcasts)."""
        socket = self.context.socket(zmq.PUB)
        socket.bind(address)
        return self._track(socket)

    def sub_socket(self, address: str, topic: bytes = b"") -> zmq.Socket:
        """Connects a SUB socket (receives broadcasts) with a subscription topic."""
        socket = self.context.socket(zmq.SUB)
        socket.connect(address)
        socket.setsockopt(zmq.SUBSCRIBE, topic)
        return self._track(socket)

    def send(self, socket: zmq.Socket, data: Dict[str, Any]) -> None:
        """Serializes dict to JSON and sends via the socket."""
        message_bytes = json.dumps(data).encode("utf-8")
        socket.send(message_bytes)

    def receive(self, socket: zmq.Socket, timeout_ms: int = 100) -> Optional[Dict[str, Any]]:
        """Non-blocking receive using a poller."""
        poller = zmq.Poller()
        poller.register(socket, zmq.POLLIN)
        
        events = dict(poller.poll(timeout_ms))
        if socket in events:
            message_bytes = socket.recv()
            try:
                return json.loads(message_bytes.decode("utf-8"))
            except json.JSONDecodeError:
                return None
        return None

    def close_all(self) -> None:
        """Closes all tracked sockets and optionally terminates the context."""
        for socket in self.sockets:
            socket.close(linger=0)
            
        if self._owns_context:
            self.context.destroy(linger=0)
