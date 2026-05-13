import time
import threading
import zmq
from abc import ABC, abstractmethod
from lilith_ai.bus.zmq_bus import LilithBus
from lilith_ai.bus.ports import PortMap, get_address

class BasePlugin(ABC):
    """Abstract base class for all Lilith AI pipeline plugins."""

    # These should be overridden in subclasses
    plugin_type: str = "base"
    name: str = "base_plugin"
    version: str = "0.0.0"
    description: str = "Base plugin class"

    def __init__(self, bus: LilithBus, config: dict):
        self.bus = bus
        self.config = config
        self.running = False
        self._thread: threading.Thread | None = None
        
        # Internally create a pub socket for logging 
        # MUST connect instead of bind so multiple plugins don't collide on the same port
        self._log_socket = self.bus.context.socket(zmq.PUB)
        self._log_socket.connect(get_address(PortMap.PIPELINE_LOG))
        self.bus._track(self._log_socket)

    @abstractmethod
    def setup(self) -> None:
        """Initialize sockets and resources. Called once before start."""
        pass

    @abstractmethod
    def run(self) -> None:
        """Main loop. Must respect self.running flag."""
        pass

    def start(self) -> None:
        """Starts the plugin in a daemon thread."""
        if self.running:
            return
            
        self.running = True
        self.setup()
        
        self._thread = threading.Thread(target=self._run_wrapper, daemon=True, name=f"Thread-{self.name}")
        self._thread.start()

    def _run_wrapper(self) -> None:
        """Wrapper to catch unhandled errors in plugin threads."""
        try:
            self.run()
        except Exception as e:
            self.log(f"Plugin crashed: {e}", level="ERROR")
            self.running = False

    def stop(self) -> None:
        """Stops the plugin and blocks until the thread joins."""
        self.running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
            if self._thread.is_alive():
                self.log("Thread failed to join within timeout.", level="WARNING")
        
        self.cleanup()

    def cleanup(self) -> None:
        """Optional override for resource teardown."""
        pass

    def log(self, message: str, level: str = "INFO") -> None:
        """Sends a structured log message to PIPELINE_LOG port via PUB socket."""
        log_payload = {
            "plugin": self.name,
            "level": level.upper(),
            "msg": message,
            "ts": time.time()
        }
        
        print(f"[{level.upper()}] [{self.name}] {message}")
        self.bus.send(self._log_socket, log_payload)
