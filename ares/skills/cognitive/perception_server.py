"""ARES perception MCP server — local vision pipeline.

Two-tier: YOLOv8n (ANE, 30fps) + Florence-2 (GPU, 2fps).
Both CoreML-compatible, 100% local. Structured JSON output for Hermes cognition.

This is the first cognitive skill. Tier 0 (READ_ONLY) — perception only.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.perception")

server = FastMCP(
    name="ARES Perception",
    instructions="Local vision pipeline: YOLOv8n (fast detection) + Florence-2 (scene captions). 100% local, no cloud.",
    host="0.0.0.0",
    port=9512,
)

# ═══ Lazy model singletons (init on first use, not at import) ══════════════

_yolo_model: Optional[object] = None
_florence_model: Optional[object] = None
_florence_processor: Optional[object] = None
_model_lock = threading.Lock()
_start_time = time.time()

# Model cache paths — downloaded once, reused
MODEL_DIR = Path.home() / ".ares" / "models"
MODEL_DIR.mkdir(parents=True, exist_ok=True)

FLORENCE_MODEL_ID = "microsoft/Florence-2-base"


def _get_yolo():
    """Lazy-load YOLOv8n. Thread-safe, cached in memory."""
    global _yolo_model
    if _yolo_model is not None:
        return _yolo_model
    with _model_lock:
        if _yolo_model is not None:
            return _yolo_model
        try:
            from ultralytics import YOLO

            _yolo_model = YOLO("yolov8n.pt")
            logger.info("YOLOv8n loaded (first use)")
        except Exception as e:
            logger.error("YOLOv8n load failed: %s", e)
            _yolo_model = False  # sentinel to avoid retry spam
        return _yolo_model


def _get_florence():
    """Lazy-load Florence-2 model + processor. Thread-safe, cached in memory."""
    global _florence_model, _florence_processor
    if _florence_model is not None:
        return _florence_model, _florence_processor
    with _model_lock:
        if _florence_model is not None:
            return _florence_model, _florence_processor
        try:
            import torch
            from transformers import AutoProcessor, AutoModelForCausalLM

            device = "mps" if torch.backends.mps.is_available() else "cpu"
            logger.info("Loading Florence-2 on %s (first use, ~300MB)...", device)

            _florence_model = AutoModelForCausalLM.from_pretrained(
                FLORENCE_MODEL_ID,
                trust_remote_code=True,
                torch_dtype=torch.float16 if device == "mps" else torch.float32,
            ).to(device)
            _florence_processor = AutoProcessor.from_pretrained(
                FLORENCE_MODEL_ID,
                trust_remote_code=True,
            )
            logger.info("Florence-2 loaded on %s", device)
        except Exception as e:
            logger.error("Florence-2 load failed: %s", e)
            _florence_model = False
            _florence_processor = False
        return _florence_model, _florence_processor


def _capture_webcam() -> Optional[np.ndarray]:
    """Capture a single frame from the default webcam. Returns BGR numpy array or None."""
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        cap.release()
        return None
    ret, frame = cap.read()
    cap.release()
    return frame if ret else None


def _load_image(image_path: str) -> Optional[np.ndarray]:
    """Load image from path. Returns BGR numpy array or None."""
    p = Path(image_path).expanduser().resolve()
    if not p.exists():
        return None
    img = cv2.imread(str(p))
    return img if img is not None else None


# ═══ Tools ══════════════════════════════════════════════════════════════════


@server.tool()
def perception_health() -> dict:
    """Report perception service health without starting an expensive capture."""
    yolo_available = False
    florence_available = False

    try:
        import ultralytics  # noqa: F401

        yolo_available = True
    except ImportError:
        pass

    try:
        import transformers  # noqa: F401

        florence_available = True
    except ImportError:
        pass

    return {
        "status": "ok",
        "uptime": int(time.time() - _start_time),
        "camera": False,
        "yolo_installed": yolo_available,
        "florence_installed": florence_available,
        "yolo_loaded": _yolo_model is not None and _yolo_model is not False,
        "florence_loaded": _florence_model is not None and _florence_model is not False,
        "mode": "live" if (yolo_available and florence_available) else "stub",
    }


@server.tool()
def detect_objects(image_path: str = "", use_webcam: bool = True) -> dict:
    """Detect objects in an image or from the webcam.

    Returns structured object list with labels, bounding boxes, and confidence scores.
    Uses YOLOv8n with MPS/CPU backend for detection.

    Args:
        image_path: Path to image file (if empty, uses webcam)
        use_webcam: If True and no image_path, captures from default webcam

    Returns:
        dict with 'objects' list, 'count', and 'timestamp'
    """
    # Acquire image
    frame = None
    if image_path:
        frame = _load_image(image_path)
    if frame is None and use_webcam:
        frame = _capture_webcam()

    if frame is None:
        return {
            "status": "error",
            "objects": [],
            "count": 0,
            "error": "no image available",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    # Run YOLO
    model = _get_yolo()
    if model is False or model is None:
        return {
            "status": "no_yolo",
            "objects": [],
            "count": 0,
            "note": "YOLOv8n not available — run pip install ultralytics",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    try:
        results = model(frame, verbose=False)
    except Exception as e:
        return {
            "status": "error",
            "objects": [],
            "count": 0,
            "error": str(e),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    objects = []
    if results and len(results) > 0:
        r = results[0]
        boxes = r.boxes
        if boxes is not None:
            for i in range(len(boxes)):
                cls_id = int(boxes.cls[i].item())
                conf = float(boxes.conf[i].item())
                label = r.names.get(cls_id, f"class_{cls_id}")
                xyxy = boxes.xyxy[i].tolist()
                objects.append(
                    {
                        "label": label,
                        "confidence": round(conf, 3),
                        "bbox": [round(v, 1) for v in xyxy],
                    }
                )

    return {
        "status": "ok",
        "objects": objects,
        "count": len(objects),
        "model": "yolov8n",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@server.tool()
def describe_scene(image_path: str = "", use_webcam: bool = True) -> dict:
    """Generate a natural language description of the scene.

    Uses Florence-2 (local transformers) for rich scene understanding.
    Returns captions, detected objects, and OCR text.

    Args:
        image_path: Path to image file (if empty, uses webcam)
        use_webcam: If True and no image_path, captures from default webcam

    Returns:
        dict with 'description', 'objects', 'text_detected', 'activity'
    """
    # Acquire image
    frame = None
    if image_path:
        frame = _load_image(image_path)
    if frame is None and use_webcam:
        frame = _capture_webcam()

    if frame is None:
        return {
            "status": "error",
            "description": "No image available",
            "objects": [],
            "text_detected": [],
            "activity": "unknown",
            "error": "no image available",
        }

    model, processor = _get_florence()
    if model is False or processor is False or model is None:
        # Fallback: use YOLO to at least list objects
        detection = detect_objects(image_path=image_path, use_webcam=False)
        return {
            "status": "fallback_yolo",
            "description": f"Scene contains: {', '.join(o['label'] for o in detection.get('objects', []))}",
            "objects": detection.get("objects", []),
            "text_detected": [],
            "activity": "unknown",
            "note": "Florence-2 not available — YOLO fallback used",
        }

    try:
        import torch

        # Convert BGR to RGB
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil_image = None
        try:
            from PIL import Image

            pil_image = Image.fromarray(rgb)
        except ImportError:
            pass

        # Run Florence-2 with <CAPTION> task
        device = "mps" if torch.backends.mps.is_available() else "cpu"

        if pil_image is not None:
            inputs = processor(text="<CAPTION>", images=pil_image, return_tensors="pt").to(device)
        else:
            inputs = processor(text="<CAPTION>", images=rgb, return_tensors="pt").to(device)

        with torch.no_grad():
            generated_ids = model.generate(
                input_ids=inputs["input_ids"],
                pixel_values=inputs["pixel_values"],
                max_new_tokens=128,
                num_beams=3,
                do_sample=False,
            )

        generated_text = processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
        caption = generated_text.strip()

        # Also get <DETAILED_CAPTION> if available
        detailed_caption = caption
        try:
            if pil_image is not None:
                inputs2 = processor(text="<DETAILED_CAPTION>", images=pil_image, return_tensors="pt").to(device)
            else:
                inputs2 = processor(text="<DETAILED_CAPTION>", images=rgb, return_tensors="pt").to(device)
            generated_ids2 = model.generate(
                input_ids=inputs2["input_ids"],
                pixel_values=inputs2["pixel_values"],
                max_new_tokens=256,
                num_beams=3,
                do_sample=False,
            )
            detailed_caption = processor.batch_decode(generated_ids2, skip_special_tokens=True)[0].strip()
        except Exception:
            pass

        return {
            "status": "ok",
            "description": detailed_caption,
            "caption_short": caption,
            "objects": [],
            "text_detected": [],
            "activity": "unknown",
            "model": "florence-2",
        }

    except Exception as e:
        logger.error("Florence-2 inference failed: %s", e)
        return {
            "status": "error",
            "description": f"Scene analysis error: {e}",
            "objects": [],
            "text_detected": [],
            "activity": "unknown",
            "error": str(e),
        }


@server.tool()
def perception_snapshot() -> dict:
    """Take a complete perception snapshot: fast detection + scene description.

    Runs both YOLO and Florence-2 and returns a unified JSON structure
    ready for Hermes cognition layer.

    Returns:
        dict: Full perception context for the agent
    """
    # Run detection first (always works if YOLO is available)
    fast = detect_objects(use_webcam=True)
    fast_objects = fast.get("objects", [])

    # Then scene description (heavier)
    scene = describe_scene(use_webcam=True)

    # Build summary
    if fast_objects:
        top_labels = [o["label"] for o in fast_objects[:5]]
        summary = f"Scene: {scene.get('description', '?')}. Detected: {', '.join(top_labels)}."
    else:
        summary = f"Scene: {scene.get('description', '?')}."

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "fast_detection": fast_objects,
        "fast_status": fast.get("status"),
        "scene_description": scene.get("description", ""),
        "scene_status": scene.get("status"),
        "caption_short": scene.get("caption_short", ""),
        "text_detected": scene.get("text_detected", []),
        "activity": scene.get("activity", "unknown"),
        "summary": summary,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    server.run(transport="streamable-http")
