"""ARES Motor Control MCP server — Dynamixel XL330 servo bus.

Manages the JP01 robot's servo bus via the Dynamixel SDK.
All angles are in degrees; raw Dynamixel units are converted internally.
XL330 position range: 0-4095 raw = 0-360°.

This is the critical physical skill. Tier 0 — direct hardware control.
"""

from __future__ import annotations

import glob
import logging
import os
import threading
import time
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.motors")

server = FastMCP(
    name="ARES Motors",
    instructions="Dynamixel XL330 servo control for JP01 robot. All angles in degrees. Safety-first: angle limits, torque limits, and auto-disable on error.",
    host="0.0.0.0",
    port=9519,
)

# ═══ Lazy Dynamixel SDK singletons ═══════════════════════════════════════════

_dynamixel_available: Optional[bool] = None
_sdk_lock = threading.Lock()

# XL330 control-table constants (Protocol 2.0)
ADDR_OPERATING_MODE = 11
ADDR_TORQUE_ENABLE = 64
ADDR_GOAL_CURRENT = 102
ADDR_PROFILE_VELOCITY = 112
ADDR_GOAL_POSITION = 116
ADDR_PRESENT_CURRENT = 126
ADDR_PRESENT_VELOCITY = 128
ADDR_PRESENT_POSITION = 132
ADDR_PRESENT_VOLTAGE = 145
ADDR_PRESENT_TEMPERATURE = 146
ADDR_MODEL_NUMBER = 0
ADDR_FIRMWARE_VERSION = 6
ADDR_BAUD_RATE = 8

LEN_GOAL_POSITION = 4
LEN_PRESENT_POSITION = 4
LEN_PROFILE_VELOCITY = 4
LEN_PRESENT_VELOCITY = 4
LEN_GOAL_CURRENT = 2
LEN_PRESENT_CURRENT = 2
LEN_MODEL_NUMBER = 2

PROTOCOL_VERSION = 2.0

# Unit conversions
RAW_TO_DEG = 360.0 / 4095.0  # ≈ 0.08789° per raw unit
DEG_TO_RAW = 4095.0 / 360.0  # ≈ 11.375 raw units per degree
VELOCITY_UNIT_DPS = 0.229 * 6.0  # 0.229 rev/min → °/s ≈ 1.374
CURRENT_UNIT_MA = 1.34  # 1.34 mA per raw unit

# Safety limits
MAX_ANGLE_DEG = 360.0
MIN_ANGLE_DEG = 0.0
MAX_TORQUE_PERCENT = 100.0


def _check_dynamixel() -> bool:
    """Lazily check if dynamixel_sdk is installed."""
    global _dynamixel_available
    if _dynamixel_available is not None:
        return _dynamixel_available
    with _sdk_lock:
        if _dynamixel_available is not None:
            return _dynamixel_available
        try:
            import dynamixel_sdk  # noqa: F401
            _dynamixel_available = True
            logger.info("dynamixel_sdk available")
        except ImportError:
            _dynamixel_available = False
            logger.warning("dynamixel_sdk not installed — motor tools will return stub errors")
        return _dynamixel_available


def _find_port(port_hint: str) -> str:
    """Auto-detect Dynamixel USB port on macOS if the hint doesn't exist."""
    if port_hint and Path(port_hint).exists():
        return port_hint

    candidates = []
    # macOS patterns
    candidates.extend(sorted(glob.glob("/dev/tty.usbmodem*")))
    candidates.extend(sorted(glob.glob("/dev/cu.usbmodem*")))
    candidates.extend(sorted(glob.glob("/dev/ttyUSB*")))
    candidates.extend(sorted(glob.glob("/dev/ttyACM*")))

    if candidates:
        chosen = candidates[0]
        logger.debug("Auto-selected port %s (hint was %s)", chosen, port_hint)
        return chosen

    # Fallback to the hint even if it doesn't exist (caller gets a clean error)
    return port_hint or "/dev/tty.usbmodem"


def _open_port(port: str, baudrate: int):
    """Open a Dynamixel PortHandler. Returns (port_handler, packet_handler) or (None, None)."""
    if not _check_dynamixel():
        return None, None

    from dynamixel_sdk import PortHandler, PacketHandler

    port_handler = PortHandler(port)
    packet_handler = PacketHandler(PROTOCOL_VERSION)

    if not port_handler.openPort():
        logger.error("Failed to open port %s", port)
        return None, None

    if not port_handler.setBaudRate(baudrate):
        logger.error("Failed to set baudrate %d on %s", baudrate, port)
        port_handler.closePort()
        return None, None

    return port_handler, packet_handler


def _close_port(port_handler):
    """Close a Dynamixel port safely."""
    if port_handler is not None:
        try:
            port_handler.closePort()
        except Exception as e:
            logger.debug("Error closing port: %s", e)


def _dxl_error(packet_handler, dxl_comm_result, dxl_error, context: str = "") -> Optional[str]:
    """Return a human-readable error string or None if success."""
    if dxl_comm_result != 0:
        msg = f"Comm error in {context}: {packet_handler.getTxRxResult(dxl_comm_result)}"
        return msg
    if dxl_error != 0:
        msg = f"Hardware error in {context}: {packet_handler.getRxPacketError(dxl_error)}"
        return msg
    return None


def _raw_to_deg(raw_val: int) -> float:
    """Convert raw Dynamixel position to degrees."""
    return float(raw_val) * RAW_TO_DEG


def _deg_to_raw(deg: float) -> int:
    """Convert degrees to raw Dynamixel position, clamped to valid range."""
    raw = int(round(deg * DEG_TO_RAW))
    return max(0, min(4095, raw))


def _velocity_dps_to_raw(dps: float) -> int:
    """Convert degrees/sec to raw profile-velocity units."""
    raw = int(abs(dps) / VELOCITY_UNIT_DPS)
    return max(0, raw)


def _raw_to_current_ma(raw_val: int) -> float:
    """Convert raw current to milliamps."""
    signed = raw_val if raw_val <= 32767 else raw_val - 65536
    return float(signed) * CURRENT_UNIT_MA


def _raw_to_voltage(raw_val: int) -> float:
    """Convert raw voltage to volts (Dynamixel reports voltage * 10)."""
    return float(raw_val) / 10.0


# ═══ Helpers for bus operations ════════════════════════════════════════════

def _read_byte(port_handler, packet_handler, servo_id: int, addr: int) -> tuple:
    """Read a 1-byte register. Returns (value, error_str)."""
    from dynamixel_sdk import COMM_SUCCESS
    val, dxl_comm_result, dxl_error = packet_handler.read1ByteTxRx(
        port_handler, servo_id, addr
    )
    err = _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"read1B id={servo_id} addr={addr}")
    if err:
        return None, err
    return val, None


def _read_word(port_handler, packet_handler, servo_id: int, addr: int) -> tuple:
    """Read a 2-byte register. Returns (value, error_str)."""
    from dynamixel_sdk import COMM_SUCCESS
    val, dxl_comm_result, dxl_error = packet_handler.read2ByteTxRx(
        port_handler, servo_id, addr
    )
    err = _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"read2B id={servo_id} addr={addr}")
    if err:
        return None, err
    return val, None


def _read_dword(port_handler, packet_handler, servo_id: int, addr: int) -> tuple:
    """Read a 4-byte register. Returns (value, error_str)."""
    from dynamixel_sdk import COMM_SUCCESS
    val, dxl_comm_result, dxl_error = packet_handler.read4ByteTxRx(
        port_handler, servo_id, addr
    )
    err = _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"read4B id={servo_id} addr={addr}")
    if err:
        return None, err
    return val, None


def _write_byte(port_handler, packet_handler, servo_id: int, addr: int, value: int) -> Optional[str]:
    """Write a 1-byte register. Returns error_str or None."""
    from dynamixel_sdk import COMM_SUCCESS
    dxl_comm_result, dxl_error = packet_handler.write1ByteTxRx(
        port_handler, servo_id, addr, value
    )
    return _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"write1B id={servo_id} addr={addr}")


def _write_word(port_handler, packet_handler, servo_id: int, addr: int, value: int) -> Optional[str]:
    """Write a 2-byte register. Returns error_str or None."""
    from dynamixel_sdk import COMM_SUCCESS
    dxl_comm_result, dxl_error = packet_handler.write2ByteTxRx(
        port_handler, servo_id, addr, value
    )
    return _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"write2B id={servo_id} addr={addr}")


def _write_dword(port_handler, packet_handler, servo_id: int, addr: int, value: int) -> Optional[str]:
    """Write a 4-byte register. Returns error_str or None."""
    from dynamixel_sdk import COMM_SUCCESS
    dxl_comm_result, dxl_error = packet_handler.write4ByteTxRx(
        port_handler, servo_id, addr, value
    )
    return _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"write4B id={servo_id} addr={addr}")


def _get_model_name(model_number: int) -> str:
    """Map known model numbers to human-readable names."""
    KNOWN = {
        1130: "XL330-M077",
        1131: "XL330-M288",
        1060: "XL430-W250",
        1020: "XM430-W210",
        1030: "XM430-W350",
        1040: "XH430-W210",
        1050: "XH430-W350",
        1080: "XM540-W150",
        1090: "XM540-W270",
        1100: "XH540-W150",
        1110: "XH540-W270",
        1120: "XH540-V150",
        1150: "XD430-T210",
        1160: "XD430-T350",
        1170: "XD540-T150",
        1180: "XD540-T270",
        1190: "2XC430-W250",
        1200: "2XL430-W250",
        1210: "XC430-W150",
        1220: "XC430-W240",
    }
    return KNOWN.get(model_number, f"Unknown({model_number})")


# ═══ Tools ══════════════════════════════════════════════════════════════════


@server.tool()
def scan_bus(port: str = "/dev/tty.usbmodem", baudrate: int = 57600) -> dict:
    """Scan the Dynamixel bus for connected servos.

    Iterates servo IDs 1-253 and returns metadata for every responsive servo.
    Auto-detects the serial port on macOS if the hint doesn't exist.
    """
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, baudrate)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port} at {baudrate}"}

    try:
        from dynamixel_sdk import COMM_SUCCESS

        found = []
        for servo_id in range(1, 254):
            try:
                model_raw, dxl_comm_result, dxl_error = packet_handler.ping(
                    port_handler, servo_id
                )
                if dxl_comm_result == COMM_SUCCESS and dxl_error == 0:
                    model_number = model_raw
                    fw_ver, _ = _read_byte(port_handler, packet_handler, servo_id, ADDR_FIRMWARE_VERSION)
                    baud, _ = _read_byte(port_handler, packet_handler, servo_id, ADDR_BAUD_RATE)
                    found.append({
                        "id": servo_id,
                        "model": _get_model_name(model_number),
                        "firmware_version": fw_ver if fw_ver is not None else -1,
                        "baudrate": baudrate,
                    })
            except Exception:
                # Device not present — expected for most IDs
                continue

        return {
            "status": "ok",
            "port": port,
            "baudrate": baudrate,
            "servos": found,
            "count": len(found),
        }
    finally:
        _close_port(port_handler)


@server.tool()
def ping(servo_id: int, port: str = "/dev/tty.usbmodem") -> dict:
    """Ping a specific servo and return its identity."""
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    if not (1 <= servo_id <= 253):
        return {"status": "error", "error": f"servo_id {servo_id} out of range 1-253"}

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, 57600)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port}"}

    try:
        model_number, dxl_comm_result, dxl_error = packet_handler.ping(
            port_handler, servo_id
        )
        if dxl_comm_result != 0 or dxl_error != 0:
            err = _dxl_error(packet_handler, dxl_comm_result, dxl_error, f"ping id={servo_id}")
            return {
                "status": "error",
                "servo_id": servo_id,
                "model_number": None,
                "firmware_version": None,
                "reachable": False,
                "error": err,
            }

        fw_ver, _ = _read_byte(port_handler, packet_handler, servo_id, ADDR_FIRMWARE_VERSION)
        return {
            "status": "ok",
            "servo_id": servo_id,
            "model_number": model_number,
            "model_name": _get_model_name(model_number),
            "firmware_version": fw_ver if fw_ver is not None else -1,
            "reachable": True,
        }
    finally:
        _close_port(port_handler)


@server.tool()
def read_position(servo_id: int, port: str = "/dev/tty.usbmodem") -> dict:
    """Read current position and telemetry from a servo.

    Returns position in degrees, raw units, load (mA), temperature (°C),
    and voltage (V).
    """
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    if not (1 <= servo_id <= 253):
        return {"status": "error", "error": f"servo_id {servo_id} out of range 1-253"}

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, 57600)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port}"}

    try:
        pos_raw, err1 = _read_dword(port_handler, packet_handler, servo_id, ADDR_PRESENT_POSITION)
        current_raw, err2 = _read_word(port_handler, packet_handler, servo_id, ADDR_PRESENT_CURRENT)
        temp_raw, err3 = _read_byte(port_handler, packet_handler, servo_id, ADDR_PRESENT_TEMPERATURE)
        volt_raw, err4 = _read_byte(port_handler, packet_handler, servo_id, ADDR_PRESENT_VOLTAGE)

        errors = [e for e in (err1, err2, err3, err4) if e]
        if errors:
            # Try to disable torque on error as a safety measure
            try:
                _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, 0)
            except Exception:
                pass
            return {
                "status": "error",
                "servo_id": servo_id,
                "error": "; ".join(errors),
            }

        position_deg = _raw_to_deg(pos_raw) if pos_raw is not None else None
        load_ma = _raw_to_current_ma(current_raw) if current_raw is not None else None
        temperature_c = float(temp_raw) if temp_raw is not None else None
        voltage_v = _raw_to_voltage(volt_raw) if volt_raw is not None else None

        return {
            "status": "ok",
            "servo_id": servo_id,
            "position_deg": round(position_deg, 2) if position_deg is not None else None,
            "position_raw": pos_raw,
            "load": round(load_ma, 1) if load_ma is not None else None,
            "temperature_c": temperature_c,
            "voltage_v": voltage_v,
        }
    finally:
        _close_port(port_handler)


@server.tool()
def move_to(
    servo_id: int,
    angle_deg: float,
    speed_dps: float = 60.0,
    torque_percent: float = 100.0,
    port: str = "/dev/tty.usbmodem",
) -> dict:
    """Move a servo to a target angle with speed and torque limits.

    Safety checks:
        - Angle clamped to [0°, 360°]
        - Torque limited to ≤ 100%
        - Servo must be in Position Control Mode
        - Previous position is read before commanding the move
    """
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    if not (1 <= servo_id <= 253):
        return {"status": "error", "error": f"servo_id {servo_id} out of range 1-253"}

    # Safety clamp
    target_deg = max(MIN_ANGLE_DEG, min(MAX_ANGLE_DEG, float(angle_deg)))
    safe_torque = max(0.0, min(MAX_TORQUE_PERCENT, float(torque_percent)))
    safe_speed = max(0.0, float(speed_dps))

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, 57600)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port}"}

    try:
        # Read previous position
        prev_raw, err = _read_dword(port_handler, packet_handler, servo_id, ADDR_PRESENT_POSITION)
        if err:
            return {"status": "error", "servo_id": servo_id, "error": err}

        previous_deg = round(_raw_to_deg(prev_raw), 2)

        # Ensure torque is enabled
        err = _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, 1)
        if err:
            return {"status": "error", "servo_id": servo_id, "error": f"torque enable failed: {err}"}

        # Set profile velocity
        vel_raw = _velocity_dps_to_raw(safe_speed)
        err = _write_dword(port_handler, packet_handler, servo_id, ADDR_PROFILE_VELOCITY, vel_raw)
        if err:
            return {"status": "error", "servo_id": servo_id, "error": f"velocity set failed: {err}"}

        # Set goal position
        goal_raw = _deg_to_raw(target_deg)
        err = _write_dword(port_handler, packet_handler, servo_id, ADDR_GOAL_POSITION, goal_raw)
        if err:
            # Auto-disable torque on write failure
            _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, 0)
            return {"status": "error", "servo_id": servo_id, "error": f"position write failed: {err}"}

        return {
            "status": "ok",
            "servo_id": servo_id,
            "target_deg": round(target_deg, 2),
            "previous_deg": previous_deg,
            "moving": True,
        }
    finally:
        _close_port(port_handler)


@server.tool()
def set_torque(servo_id: int, enable: bool, port: str = "/dev/tty.usbmodem") -> dict:
    """Enable or disable torque on a servo."""
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    if not (1 <= servo_id <= 253):
        return {"status": "error", "error": f"servo_id {servo_id} out of range 1-253"}

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, 57600)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port}"}

    try:
        value = 1 if enable else 0
        err = _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, value)
        if err:
            return {"status": "error", "servo_id": servo_id, "error": err}

        return {
            "status": "ok",
            "servo_id": servo_id,
            "torque_enabled": enable,
        }
    finally:
        _close_port(port_handler)


@server.tool()
def set_operating_mode(servo_id: int, mode: str = "position", port: str = "/dev/tty.usbmodem") -> dict:
    """Set the operating mode of a servo.

    Modes:
        - "position"           → Position Control Mode (3)
        - "velocity"           → Velocity Control Mode (1)
        - "current"            → Current (Torque) Control Mode (0)
        - "extended_position"  → Extended Position Control Mode (4, multi-turn)

    Torque is automatically disabled before changing mode and re-enabled after
    only if it was previously on.
    """
    if not _check_dynamixel():
        return {"status": "error", "error": "dynamixel_sdk not available"}

    if not (1 <= servo_id <= 253):
        return {"status": "error", "error": f"servo_id {servo_id} out of range 1-253"}

    MODE_MAP = {
        "position": 3,
        "velocity": 1,
        "current": 0,
        "torque": 0,
        "extended_position": 4,
        "extended": 4,
        "multi_turn": 4,
    }

    mode_norm = mode.strip().lower()
    if mode_norm not in MODE_MAP:
        return {
            "status": "error",
            "error": f"unknown mode '{mode}'. Choose from: position, velocity, current, extended_position",
        }

    mode_value = MODE_MAP[mode_norm]
    canonical = {3: "position", 1: "velocity", 0: "current", 4: "extended_position"}[mode_value]

    port = _find_port(port)
    port_handler, packet_handler = _open_port(port, 57600)
    if port_handler is None:
        return {"status": "error", "error": f"could not open port {port}"}

    try:
        # Read current torque state
        torque_state, _ = _read_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE)
        was_enabled = torque_state == 1

        # Disable torque to allow mode change
        if was_enabled:
            err = _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, 0)
            if err:
                return {"status": "error", "servo_id": servo_id, "error": f"torque disable failed: {err}"}

        # Write new mode
        err = _write_byte(port_handler, packet_handler, servo_id, ADDR_OPERATING_MODE, mode_value)
        if err:
            return {"status": "error", "servo_id": servo_id, "error": f"mode set failed: {err}"}

        # Re-enable torque if it was on
        if was_enabled:
            _write_byte(port_handler, packet_handler, servo_id, ADDR_TORQUE_ENABLE, 1)

        return {
            "status": "ok",
            "servo_id": servo_id,
            "mode": canonical,
            "mode_value": mode_value,
        }
    finally:
        _close_port(port_handler)


@server.tool()
def motor_health() -> dict:
    """Report motor service health without touching hardware."""
    return {
        "status": "ok",
        "dynamixel_sdk": _check_dynamixel(),
        "port_candidates": sorted(
            glob.glob("/dev/tty.usbmodem*")
            + glob.glob("/dev/cu.usbmodem*")
            + glob.glob("/dev/ttyUSB*")
            + glob.glob("/dev/ttyACM*")
        ),
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    server.run(transport="streamable-http")
