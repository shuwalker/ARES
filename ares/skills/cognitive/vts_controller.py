"""
ARES VTS Controller — bridges AI cognition to Live2D avatar via VTube Studio.

Connects to VTube Studio (Steam, macOS native) over its WebSocket API.
Maps ARES's 6-state face machine to Live2D parameters in real-time.

Dependencies: pyvts, websocket-client
"""
from __future__ import annotations

import asyncio
import json
import logging
import threading
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Callable

logger = logging.getLogger(__name__)


class AvatarExpression(Enum):
    """High-level expressions the AI can request."""
    NEUTRAL = "neutral"
    HAPPY = "happy"
    CURIOUS = "curious"
    THINKING = "thinking"
    SURPRISED = "surprised"
    CONCERNED = "concerned"
    EXCITED = "excited"
    SLEEPY = "sleepy"


@dataclass
class Live2DParams:
    """Live2D parameter state. These are the universal VTS parameter names."""
    # Eye params
    EyeOpenLeft: float = 1.0
    EyeOpenRight: float = 1.0
    EyeX: float = 0.0          # -1 left, 0 center, 1 right
    EyeY: float = 0.0          # -1 down, 0 center, 1 up
    BrowY: float = 0.0         # -1 lowered, 0 neutral, 1 raised
    EyeSmile: float = 0.0      # 0 neutral, 1 happy squint

    # Mouth params
    MouthOpen: float = 0.0     # 0 closed, 1 full open
    MouthSmile: float = 0.0    # -1 frown, 0 neutral, 1 smile
    MouthX: float = 0.0        # -1 left, 0 center, 1 right

    # Head/body
    FaceAngleX: float = 0.0    # head tilt left/right
    FaceAngleY: float = 0.0    # head tilt up/down
    FaceAngleZ: float = 0.0    # head rotation
    BodyAngleX: float = 0.0
    BodyAngleY: float = 0.0
    BodyAngleZ: float = 0.0

    # Breathing / idle
    Breath: float = 0.0        # animated by VTS, we just set amplitude
    Cheek: float = 0.0         # blush 0-1

    # Hand/arm (model-dependent)
    ArmLeft: float = 0.0
    ArmRight: float = 0.0

    def to_dict(self) -> dict:
        return {
            k: v for k, v in self.__dict__.items()
            if not k.startswith("_")
        }

    def lerp(self, target: "Live2DParams", t: float) -> "Live2DParams":
        """Linear interpolation between current and target."""
        result = Live2DParams()
        for key in self.__dict__:
            if key.startswith("_"):
                continue
            a = getattr(self, key)
            b = getattr(target, key)
            setattr(result, key, a + (b - a) * t)
        return result


# ═══════════════════════════════════════════════════════════════════════════
# Expression → Live2D parameter mapping
# ═══════════════════════════════════════════════════════════════════════════

EXPRESSION_MAP: dict[AvatarExpression, Live2DParams] = {
    AvatarExpression.NEUTRAL: Live2DParams(
        EyeOpenLeft=0.85, EyeOpenRight=0.85,
        MouthSmile=0.0, BrowY=0.0, EyeSmile=0.0,
        Cheek=0.0,
    ),
    AvatarExpression.HAPPY: Live2DParams(
        EyeOpenLeft=1.0, EyeOpenRight=1.0,
        MouthSmile=0.8, BrowY=0.3, EyeSmile=0.6,
        Cheek=0.3,
    ),
    AvatarExpression.CURIOUS: Live2DParams(
        EyeOpenLeft=1.0, EyeOpenRight=1.0,
        MouthSmile=0.2, BrowY=0.6, EyeX=0.05,
        Cheek=0.1,
    ),
    AvatarExpression.THINKING: Live2DParams(
        EyeOpenLeft=0.6, EyeOpenRight=0.6,
        MouthSmile=-0.1, BrowY=-0.2, EyeY=0.15,
        Cheek=0.0,
    ),
    AvatarExpression.SURPRISED: Live2DParams(
        EyeOpenLeft=1.0, EyeOpenRight=1.0,
        MouthOpen=0.3, MouthSmile=0.1, BrowY=0.8,
        Cheek=0.2,
    ),
    AvatarExpression.CONCERNED: Live2DParams(
        EyeOpenLeft=0.8, EyeOpenRight=0.8,
        MouthSmile=-0.4, BrowY=-0.5,
        Cheek=0.0,
    ),
    AvatarExpression.EXCITED: Live2DParams(
        EyeOpenLeft=1.0, EyeOpenRight=1.0,
        MouthOpen=0.2, MouthSmile=1.0, BrowY=0.5, EyeSmile=0.8,
        Cheek=0.5,
    ),
    AvatarExpression.SLEEPY: Live2DParams(
        EyeOpenLeft=0.15, EyeOpenRight=0.15,
        MouthSmile=0.0, BrowY=-0.1,
        Cheek=0.0,
    ),
}


# ═══════════════════════════════════════════════════════════════════════════
# VTube Studio Controller
# ═══════════════════════════════════════════════════════════════════════════

class VTSController:
    """Manages connection to VTube Studio and drives avatar parameters."""

    def __init__(self, host: str = "127.0.0.1", port: int = 8001):
        self.host = host
        self.port = port
        self._client = None
        self._connected = False
        self._current_params = Live2DParams()
        self._target_params = Live2DParams()
        self._current_expression = AvatarExpression.NEUTRAL
        self._lock = threading.Lock()
        self._running = False
        self._thread: Optional[threading.Thread] = None

        # Animation state
        self._blink_timer = 0.0
        self._blink_interval = 3.5  # seconds between blinks
        self._is_blinking = False
        self._blink_progress = 0.0
        self._transition_start = 0.0
        self._transition_duration = 0.3  # seconds for expression transitions

    @property
    def connected(self) -> bool:
        return self._connected

    @property
    def current_expression(self) -> AvatarExpression:
        return self._current_expression

    def connect(self) -> bool:
        """Connect to VTube Studio WebSocket API."""
        try:
            import pyvts
            self._client = pyvts.vts(
                plugin_info={
                    "plugin_name": "ARES Companion",
                    "developer": "Jenkins Robotics",
                    "authentication_token_path": "./vts_token.txt",
                }
            )
            self._client.connect(self.host, self.port)
            self._client.request_authenticate_token()
            self._client.request_authenticate()

            self._connected = True
            logger.info(f"Connected to VTube Studio at {self.host}:{self.port}")
            return True
        except Exception as e:
            logger.warning(f"VTS connection failed: {e}")
            self._connected = False
            return False

    def disconnect(self):
        """Disconnect from VTube Studio."""
        self._running = False
        if self._client:
            try:
                self._client.close()
            except Exception:
                pass
        self._connected = False
        self._client = None

    def set_expression(self, expression: AvatarExpression):
        """Set the target expression. Transitions smoothly."""
        with self._lock:
            self._current_expression = expression
            self._target_params = EXPRESSION_MAP.get(expression, EXPRESSION_MAP[AvatarExpression.NEUTRAL])
            self._transition_start = time.time()

    def set_mouth_open(self, amount: float):
        """Set mouth open amount (for lip sync). 0-1."""
        with self._lock:
            self._target_params.MouthOpen = max(0.0, min(1.0, amount))

    def set_gaze(self, x: float, y: float):
        """Set gaze direction. -1 to 1."""
        with self._lock:
            self._target_params.EyeX = max(-1.0, min(1.0, x))
            self._target_params.EyeY = max(-1.0, min(1.0, y))

    def start_animation_loop(self, fps: int = 30):
        """Start background thread that streams parameters to VTS."""
        self._running = True
        self._thread = threading.Thread(target=self._animation_loop, args=(fps,), daemon=True)
        self._thread.start()

    def _animation_loop(self, fps: int):
        """Main animation loop — computes interpolated params and sends to VTS."""
        frame_time = 1.0 / fps
        last_send = time.time()

        while self._running and self._connected:
            now = time.time()
            dt = now - last_send
            if dt < frame_time:
                time.sleep(frame_time - dt)
                continue

            last_send = now

            with self._lock:
                # Compute interpolation factor for expression transitions
                elapsed = now - self._transition_start
                t = min(elapsed / self._transition_duration, 1.0)
                # Ease in-out
                t = t * t * (3 - 2 * t)

                params = self._current_params.lerp(self._target_params, t)
                self._current_params = params

                # Blink animation
                self._blink_timer += frame_time
                if self._is_blinking:
                    self._blink_progress += frame_time / 0.12  # 120ms blink
                    if self._blink_progress >= 1.0:
                        self._is_blinking = False
                        self._blink_progress = 0.0
                        self._blink_timer = 0.0
                    else:
                        # Quick close then open
                        blink = abs(self._blink_progress * 2 - 1)
                        params.EyeOpenLeft *= blink
                        params.EyeOpenRight *= blink
                elif self._blink_timer > self._blink_interval:
                    self._is_blinking = True
                    self._blink_progress = 0.0

            # Send to VTS
            try:
                param_dict = params.to_dict()
                self._client.request(
                    self._client.vts_request.requestInjectParameterDataRequest(param_dict)
                )
            except Exception as e:
                logger.debug(f"VTS param inject failed: {e}")
                # Try to reconnect
                try:
                    self._client.request(
                        self._client.vts_request.requestInjectParameterDataRequest(params.to_dict())
                    )
                except Exception:
                    logger.warning("VTS reconnection failed — avatar may be frozen")


# ═══════════════════════════════════════════════════════════════════════════
# Singleton
# ═══════════════════════════════════════════════════════════════════════════

_controller: Optional[VTSController] = None


def get_controller() -> VTSController:
    """Get or create the VTS controller singleton."""
    global _controller
    if _controller is None:
        _controller = VTSController()
    return _controller


def connect_avatar() -> bool:
    """Connect to VTube Studio and start the animation loop."""
    ctrl = get_controller()
    if ctrl.connect():
        ctrl.start_animation_loop()
        return True
    return False


def set_expression(expression: AvatarExpression):
    """Set the avatar's expression from anywhere in the codebase."""
    get_controller().set_expression(expression)


def speak_animation(audio_amplitude: float = 0.5):
    """Drive mouth open for speaking."""
    get_controller().set_mouth_open(audio_amplitude)


def look_at(x: float, y: float):
    """Make the avatar look at a point on screen."""
    get_controller().set_gaze(x, y)


def avatar_connected() -> bool:
    """Check if avatar is live."""
    return get_controller().connected
