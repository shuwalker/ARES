"""
ARES Perception MCP Server — Eyes for the entity.

Two-tier local vision pipeline:
  YOLOv8n (ANE, ~30fps) → fast object detection
  Florence-2 (GPU, ~2fps) → rich scene captions, OCR, activity

MCP server binds :9512, StreamableHTTP. Tools auto-discovered by Hermes.
"""
from __future__ import annotations

import json
import time
import io
import base64
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

import cv2
import torch
from mcp.server.fastmcp import FastMCP

# ── Server ────────────────────────────────────────────────────────────────
server = FastMCP(
    name="ARES Perception",
    instructions="Local vision pipeline: YOLOv8n + Florence-2. 100% local on Mac Studio.",
    host="0.0.0.0",
    port=9512,
)

# ── Models (lazy load) ────────────────────────────────────────────────────
_yolo = None
_florence = None
_florence_processor = None
_model_lock = Lock()

def _get_yolo():
    global _yolo
    if _yolo is None:
        with _model_lock:
            if _yolo is None:
                from ultralytics import YOLO
                _yolo = YOLO("yolov8n.pt")
    return _yolo

def _get_florence():
    global _florence, _florence_processor
    if _florence is None:
        with _model_lock:
            if _florence is None:
                from transformers import AutoProcessor, AutoModelForCausalLM
                _florence = AutoModelForCausalLM.from_pretrained(
                    "microsoft/Florence-2-base", trust_remote_code=True
                ).to("mps" if torch.backends.mps.is_available() else "cpu")
                _florence_processor = AutoProcessor.from_pretrained(
                    "microsoft/Florence-2-base", trust_remote_code=True
                )
    return _florence, _florence_processor

# ── Camera ─────────────────────────────────────────────────────────────────
CAMERA_ID = 0  # default: Insta360 Link 2

def _capture_frame(camera_id: int = CAMERA_ID) -> bytes | None:
    """Capture a single frame from webcam. Returns JPEG bytes or None."""
    cap = cv2.VideoCapture(camera_id)
    if not cap.isOpened():
        cap.release()
        return None

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    # Warm up — first frames are often dark
    for _ in range(5):
        cap.read()

    ret, frame = cap.read()
    cap.release()

    if not ret or frame is None:
        return None

    _, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return jpeg.tobytes()


def _frame_to_pil(jpeg_bytes: bytes):
    """Convert JPEG bytes to PIL Image."""
    from PIL import Image
    return Image.open(io.BytesIO(jpeg_bytes))


# ── Tools ──────────────────────────────────────────────────────────────────

@server.tool()
def detect_objects() -> dict:
    """Look through the webcam and detect objects in the room.

    Uses YOLOv8n running on Apple Neural Engine for fast, local detection.
    Returns what's visible: people, objects, furniture, equipment.

    Returns:
        dict: objects list with labels, confidence scores, and counts
    """
    jpeg = _capture_frame()
    if jpeg is None:
        return {"status": "no_camera", "objects": [], "error": "Camera not available"}

    try:
        model = _get_yolo()
        results = model(_frame_to_pil(jpeg), verbose=False)

        objects = []
        if results and len(results) > 0:
            for r in results:
                for box in r.boxes:
                    objects.append({
                        "label": r.names[int(box.cls[0])],
                        "confidence": round(float(box.conf[0]), 3),
                        "box": [round(float(x), 1) for x in box.xyxy[0].tolist()],
                    })

        # Count by label
        counts = {}
        for obj in objects:
            label = obj["label"]
            counts[label] = counts.get(label, 0) + 1

        return {
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "objects": objects,
            "counts": counts,
            "summary": ", ".join(f"{v} {k}{'s' if v > 1 else ''}" for k, v in sorted(counts.items())) or "nothing detected",
        }
    except Exception as e:
        return {"status": "error", "error": str(e), "objects": []}


@server.tool()
def describe_scene() -> dict:
    """Describe what's happening in the room right now.

    Uses Florence-2 running on GPU for rich scene understanding.
    Returns a natural language description, detected text (OCR), and activity.

    Returns:
        dict: description, objects, text, activity
    """
    jpeg = _capture_frame()
    if jpeg is None:
        return {"status": "no_camera", "description": "Camera unavailable"}

    try:
        model, processor = _get_florence()
        image = _frame_to_pil(jpeg)

        # Run tasks
        results = {}
        for task in ["<OD>", "<CAPTION>", "<DETAILED_CAPTION>", "<OCR>"]:
            try:
                inputs = processor(text=task, images=image, return_tensors="pt").to(model.device)
                generated = model.generate(
                    input_ids=inputs["input_ids"],
                    pixel_values=inputs["pixel_values"],
                    max_new_tokens=256,
                    num_beams=3,
                )
                text = processor.batch_decode(generated, skip_special_tokens=True)[0]
                results[task.strip("<>").lower()] = text
            except Exception:
                results[task.strip("<>").lower()] = ""

        return {
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "caption": results.get("caption", ""),
            "detailed": results.get("detailed_caption", ""),
            "objects": results.get("od", ""),
            "text_visible": results.get("ocr", ""),
        }
    except Exception as e:
        return {"status": "error", "error": str(e)}


@server.tool()
def look() -> dict:
    """Full perception snapshot: fast object detection + scene understanding.

    Runs both YOLO and Florence-2 and returns unified context for the agent's cognition layer.
    Use this to understand what's happening around you.

    Returns:
        dict: Complete perception context
    """
    jpeg = _capture_frame()
    if jpeg is None:
        return {"status": "no_camera", "error": "Camera not available"}

    # Fast detection first
    fast = detect_objects()

    # Scene description
    scene = describe_scene()

    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "quick": fast.get("summary", ""),
        "detail": scene.get("detailed", scene.get("caption", "")),
        "objects": fast.get("objects", []),
        "counts": fast.get("counts", {}),
        "text_visible": scene.get("text_visible", ""),
    }


@server.tool()
def perception_health() -> dict:
    """Check perception system health: camera, models, device."""
    status = {"camera": False, "yolo": False, "florence": False, "device": "cpu"}

    # Camera
    cap = cv2.VideoCapture(CAMERA_ID)
    status["camera"] = cap.isOpened()
    if status["camera"]:
        w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
        h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
        status["camera_resolution"] = f"{int(w)}x{int(h)}"
    cap.release()

    # Device
    if torch.backends.mps.is_available():
        status["device"] = "mps"
    elif torch.cuda.is_available():
        status["device"] = "cuda"

    # Models
    try:
        _get_yolo()
        status["yolo"] = True
    except Exception:
        pass

    return status


if __name__ == "__main__":
    server.run(transport="streamable-http")
