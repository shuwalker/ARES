"""ARES CAD MCP Server — 3D parts, meshes, and parametric design.

Tools:
- load_step      : Read STEP/IGES/STL/OBJ, return mesh stats
- analyze_part   : Center-of-mass, inertia, watertight check, wall thickness
- generate_bracket : Parametric bracket via CadQuery → STEP
- convert_mesh   : Convert between 3D formats
- slice_for_3dprint : Printability analysis (overhangs, supports, time)
- compare_parts  : Compare two meshes (deviation, volume diff)

MCP :9515, StreamableHTTP.
"""

from __future__ import annotations

import json
import logging
import math
import os
import tempfile
import time
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.cad")

server = FastMCP(
    name="ARES CAD",
    instructions="3D CAD tools: load/analyze parts, generate parametric brackets, convert meshes, 3D-print analysis, compare parts.",
    host="0.0.0.0",
    port=9515,
)

# ═══ Lazy module singletons (init on first use) ════════════════════════════

_cq: Optional[object] = None
_trimesh: Optional[object] = None
_model_lock = False  # simple flag; GIL protects module import
_start_time = time.time()


def _get_cadquery():
    """Lazy-load CadQuery."""
    global _cq
    if _cq is not None:
        return _cq
    try:
        import cadquery as cq
        _cq = cq
    except Exception as e:
        logger.error("CadQuery import failed: %s", e)
        _cq = False
    return _cq


def _get_trimesh():
    """Lazy-load trimesh."""
    global _trimesh
    if _trimesh is not None:
        return _trimesh
    try:
        import trimesh as tm
        _trimesh = tm
    except Exception as e:
        logger.error("trimesh import failed: %s", e)
        _trimesh = False
    return _trimesh


def _load_mesh(path: str) -> Optional[object]:
    """Load mesh via trimesh or CadQuery. Returns mesh or None."""
    p = Path(path).expanduser().resolve()
    if not p.exists():
        return None
    tm = _get_trimesh()
    ext = p.suffix.lower()

    if ext in {".stl", ".obj", ".ply", ".glb", ".gltf", ".3mf"}:
        if tm is False or tm is None:
            return None
        try:
            mesh = tm.load(str(p))
            if isinstance(mesh, tm.Scene):
                mesh = mesh.dump(concatenate=True)
            return mesh
        except Exception as e:
            logger.error("trimesh load failed: %s", e)
            return None

    if ext in {".step", ".stp", ".iges", ".igs"}:
        cq = _get_cadquery()
        if cq is not False and cq is not None:
            try:
                shape = cq.importers.importStep(str(p))
                if shape is not None:
                    # Convert to trimesh for analysis
                    val = shape.val()
                    tess = val.tessellate(tolerance=0.01)
                    if tess is not None and tm is not False and tm is not None:
                        verts = tess[0]
                        faces = tess[1]
                        return tm.Trimesh(vertices=verts, faces=faces)
            except Exception:
                pass
        # Fallback: trimesh may have STEP support via Assimp
        if tm is not False and tm is not None:
            try:
                mesh = tm.load(str(p))
                if isinstance(mesh, tm.Scene):
                    mesh = mesh.dump(concatenate=True)
                return mesh
            except Exception as e:
                logger.error("trimesh STEP fallback failed: %s", e)
                return None

    return None


def _mesh_stats(mesh) -> dict:
    """Return generic mesh statistics dict."""
    if mesh is None:
        return {}
    bounds = mesh.bounds
    extents = mesh.extents if hasattr(mesh, "extents") else (bounds[1] - bounds[0] if bounds is not None else [0, 0, 0])
    return {
        "vertices": int(len(mesh.vertices)),
        "faces": int(len(mesh.faces)),
        "bounding_box": {
            "min": [round(float(v), 4) for v in bounds[0]],
            "max": [round(float(v), 4) for v in bounds[1]],
        },
        "extents": [round(float(v), 4) for v in extents],
        "volume": round(float(mesh.volume), 4) if hasattr(mesh, "volume") and mesh.volume is not None else None,
        "surface_area": round(float(mesh.area), 4) if hasattr(mesh, "area") and mesh.area is not None else None,
        "watertight": bool(mesh.is_watertight) if hasattr(mesh, "is_watertight") else None,
    }


def _format_path(path: str) -> str:
    return str(Path(path).expanduser().resolve())


# ═══ Tools ══════════════════════════════════════════════════════════════════


@server.tool()
def load_step(path: str) -> dict:
    """Load a STEP/IGES/STL/OBJ file and return mesh statistics.

    Args:
        path: Absolute or ~-expanded path to the 3D file.

    Returns:
        dict: vertices, faces, bounding_box dimensions, volume, surface_area.
    """
    path = _format_path(path)
    mesh = _load_mesh(path)
    if mesh is None:
        return {"status": "error", "error": f"Could not load mesh from {path}"}

    stats = _mesh_stats(mesh)
    stats["status"] = "ok"
    stats["path"] = path
    return stats


@server.tool()
def analyze_part(path: str) -> dict:
    """Deep analysis of a 3D part.

    Args:
        path: Path to the 3D file.

    Returns:
        dict: center_of_mass, moment_of_inertia, bounding_box, watertight, volume, surface_area,
              wall_thickness_estimate, thin_walls_detected.
    """
    path = _format_path(path)
    mesh = _load_mesh(path)
    if mesh is None:
        return {"status": "error", "error": f"Could not load mesh from {path}"}

    volume = float(mesh.volume) if hasattr(mesh, "volume") and mesh.volume is not None else math.nan
    surface_area = float(mesh.area) if hasattr(mesh, "area") and mesh.area is not None else math.nan
    watertight = bool(mesh.is_watertight) if hasattr(mesh, "is_watertight") else None
    bounds = mesh.bounds
    extents = [round(float(v), 4) for v in mesh.extents] if hasattr(mesh, "extents") else [None, None, None]

    center_of_mass = None
    inertia = None
    try:
        center_of_mass = [round(float(v), 4) for v in mesh.center_mass]
    except Exception:
        try:
            center_of_mass = [round(float(v), 4) for v in mesh.centroid]
        except Exception:
            pass

    try:
        inertia = mesh.moment_inertia
        inertia = {k: round(float(v), 4) for k, v in inertia.items()} if isinstance(inertia, dict) else str(inertia)
    except Exception:
        inertia = None

    # Wall thickness via ray queries
    thickness_estimate = None
    thin_walls = False
    try:
        tm = _get_trimesh()
        if tm is not False and tm is not None:
            thickness = tm.proximity.thickness(mesh, mesh.vertices[:200])
            thickness_estimate = round(float(thickness.mean()), 4) if thickness is not None and len(thickness) else None
            if thickness_estimate is not None and thickness_estimate < 1.0:
                thin_walls = True
    except Exception:
        pass

    return {
        "status": "ok",
        "path": path,
        "volume": round(volume, 4) if not math.isnan(volume) else None,
        "surface_area": round(surface_area, 4) if not math.isnan(surface_area) else None,
        "watertight": watertight,
        "bounding_box": {
            "min": [round(float(v), 4) for v in bounds[0]],
            "max": [round(float(v), 4) for v in bounds[1]],
        },
        "extents": extents,
        "center_of_mass": center_of_mass,
        "moment_of_inertia": inertia,
        "wall_thickness_estimate_mm": thickness_estimate,
        "thin_walls_detected": thin_walls,
    }


@server.tool()
def generate_bracket(params: str) -> dict:
    """Generate a parametric mounting bracket and export as STEP.

    Args:
        params: JSON string with keys:
            width_mm, height_mm, thickness_mm, hole_diameter_mm,
            hole_count, hole_pattern (linear/grid/circle), fillet_mm

    Returns:
        dict: path to exported STEP file.
    """
    cq = _get_cadquery()
    if cq is False or cq is None:
        return {"status": "error", "error": "CadQuery not available"}

    try:
        p = json.loads(params) if isinstance(params, str) else params
    except Exception:
        return {"status": "error", "error": "params must be valid JSON string"}

    w = float(p.get("width_mm", 50))
    h = float(p.get("height_mm", 50))
    t = float(p.get("thickness_mm", 5))
    hd = float(p.get("hole_diameter_mm", 5))
    hc = int(p.get("hole_count", 4))
    pattern = str(p.get("hole_pattern", "grid")).lower()
    fillet = float(p.get("fillet_mm", 1.0))

    # Build bracket base
    bracket = cq.Workplane("XY").box(w, h, t)
    if fillet > 0:
        bracket = bracket.edges().fillet(fillet)

    # Cut holes
    if hd > 0 and hc > 0:
        if pattern == "linear":
            spacing = w / (hc + 1)
            x_positions = [(-w / 2) + (i + 1) * spacing for i in range(hc)]
            for x in x_positions:
                bracket = bracket.faces("<Z").workplane().hole(hd, depth=t).moveTo(0, 0)
                # Re-center after hole
                bracket = bracket.moveTo(0, 0)
            # Simpler pattern: use arrayOfHoles or linearPattern
            bracket = cq.Workplane("XY").box(w, h, t).edges().fillet(fillet) if fillet > 0 else cq.Workplane("XY").box(w, h, t)
            bracket = bracket.faces("<Z").workplane()
            if hc > 1:
                bracket = bracket.rarray(xCount=hc, yCount=1, xSpacing=w / (hc + 1) if hc > 1 else w, ySpacing=h).hole(hd, depth=t)
            else:
                bracket = bracket.hole(hd, depth=t)
        elif pattern == "grid":
            cols = max(1, int(math.ceil(math.sqrt(hc))))
            rows = max(1, int(math.ceil(hc / cols)))
            xsp = w / (cols + 1) if cols > 1 else w
            ysp = h / (rows + 1) if rows > 1 else h
            bracket = cq.Workplane("XY").box(w, h, t)
            if fillet > 0:
                bracket = bracket.edges().fillet(fillet)
            bracket = bracket.faces("<Z").workplane().rarray(xCount=cols, yCount=rows, xSpacing=xsp, ySpacing=ysp).hole(hd, depth=t)
        elif pattern == "circle":
            radius = min(w, h) * 0.35
            bracket = cq.Workplane("XY").box(w, h, t)
            if fillet > 0:
                bracket = bracket.edges().fillet(fillet)
            bracket = bracket.faces("<Z").workplane()
            angles = [i * (360 / hc) for i in range(hc)]
            for angle in angles:
                x = radius * math.cos(math.radians(angle))
                y = radius * math.sin(math.radians(angle))
                bracket = bracket.hole(hd, depth=t).moveTo(x, y)
        else:
            bracket = cq.Workplane("XY").box(w, h, t)
            if fillet > 0:
                bracket = bracket.edges().fillet(fillet)
            bracket = bracket.faces("<Z").workplane().hole(hd, depth=t)

    out_path = Path("/tmp") / f"ares_bracket_{int(time.time())}.step"
    cq.exporters.export(bracket, str(out_path))
    return {"status": "ok", "path": str(out_path), "params": p}


@server.tool()
def convert_mesh(path: str, target_format: str) -> dict:
    """Convert between 3D mesh formats.

    Args:
        path: Source file path.
        target_format: Target extension without dot (stl, obj, usdz, glb, ply, step).

    Returns:
        dict: output_file path.
    """
    path = _format_path(path)
    ext = Path(path).suffix.lower()
    target = target_format.lower().lstrip(".")

    tm = _get_trimesh()
    cq = _get_cadquery()
    mesh = _load_mesh(path)

    out_path = Path(tempfile.gettempdir()) / f"ares_convert_{int(time.time())}.{target}"

    # STEP export via CadQuery if we have a CQ shape
    if target in {"step", "stp"} and cq is not False and cq is not None and ext in {".step", ".stp", ".iges", ".igs"}:
        try:
            shape = cq.importers.importStep(path)
            cq.exporters.export(shape, str(out_path))
            return {"status": "ok", "output": str(out_path), "source": path}
        except Exception as e:
            return {"status": "error", "error": f"CadQuery STEP export failed: {e}"}

    if mesh is None:
        return {"status": "error", "error": f"Could not load mesh from {path}"}

    if tm is False or tm is None:
        return {"status": "error", "error": "trimesh not available"}

    try:
        if target == "usdz":
            # USDZ not native in trimesh; export GLB and note
            intermediate = out_path.with_suffix(".glb")
            mesh.export(str(intermediate))
            return {"status": "ok", "output": str(intermediate), "note": "USDZ requires usd-core; exported GLB fallback", "source": path}
        else:
            mesh.export(str(out_path))
            return {"status": "ok", "output": str(out_path), "source": path}
    except Exception as e:
        return {"status": "error", "error": f"Export failed: {e}"}


@server.tool()
def slice_for_3dprint(path: str, layer_height: float = 0.2) -> dict:
    """Analyze a mesh for 3D printability.

    Args:
        path: Path to STL/OBJ/PLY/etc.
        layer_height: Layer thickness in mm (default 0.2).

    Returns:
        dict: overhang_percentage, need_support, estimated_time_minutes, material_volume_cm3, bounding_box.
    """
    path = _format_path(path)
    tm = _get_trimesh()
    mesh = _load_mesh(path)
    if mesh is None:
        return {"status": "error", "error": f"Could not load mesh from {path}"}

    if tm is False or tm is None:
        return {"status": "error", "error": "trimesh not available"}

    bounds = mesh.bounds
    extents = mesh.extents
    height_mm = float(extents[2]) if len(extents) > 2 else 0.0
    layers = max(1, int(height_mm / layer_height))

    # Overhang analysis
    face_normals = mesh.face_normals if hasattr(mesh, "face_normals") else None
    overhang_faces = 0
    if face_normals is not None:
        # Faces pointing downward beyond ~45° need support
        z_down = face_normals[:, 2]
        overhang_faces = int((z_down < -0.707).sum())

    total_faces = len(mesh.faces)
    overhang_pct = round(100.0 * overhang_faces / total_faces, 2) if total_faces else 0.0
    need_support = overhang_pct > 5.0 or not mesh.is_watertight

    # Volume in cm³
    vol_cm3 = round(float(mesh.volume) / 1000.0, 3) if hasattr(mesh, "volume") and mesh.volume is not None else 0.0

    # Rough estimate: 1 cm³ ≈ 10-20 min for FDM depending on infill
    est_time = round(vol_cm3 * 15, 1)

    # Surface area ratio (higher ratio = more supports / slower)
    sa = float(mesh.area) if hasattr(mesh, "area") and mesh.area is not None else 0.0

    return {
        "status": "ok",
        "path": path,
        "layer_height_mm": layer_height,
        "layers": layers,
        "overhang_percentage": overhang_pct,
        "overhang_faces": overhang_faces,
        "need_support": need_support,
        "estimated_print_time_minutes": est_time,
        "material_volume_cm3": vol_cm3,
        "surface_area_mm2": round(sa, 3),
        "bounding_box_mm": {
            "x": round(float(extents[0]), 3),
            "y": round(float(extents[1]), 3),
            "z": round(float(extents[2]), 3),
        },
        "watertight": bool(mesh.is_watertight) if hasattr(mesh, "is_watertight") else None,
    }


@server.tool()
def compare_parts(path_a: str, path_b: str) -> dict:
    """Compare two meshes: deviation, volume difference, chamfer distance.

    Args:
        path_a: Path to first mesh.
        path_b: Path to second mesh.

    Returns:
        dict: hausdorff_distance, volume_diff, volume_diff_percent, surface_area_diff.
    """
    path_a = _format_path(path_a)
    path_b = _format_path(path_b)
    tm = _get_trimesh()
    m_a = _load_mesh(path_a)
    m_b = _load_mesh(path_b)

    if m_a is None or m_b is None:
        return {"status": "error", "error": "Could not load one or both meshes"}

    if tm is False or tm is None:
        return {"status": "error", "error": "trimesh not available"}

    # Hausdorff distance
    try:
        hausdorff = tm.proximity.hausdorff_distance(m_a, m_b)
        hausdorff = round(float(hausdorff), 4)
    except Exception as e:
        hausdorff = None
        logger.debug("hausdorff failed: %s", e)

    # Chamfer distance approximation (mean of nearest distances)
    try:
        nearest_ab, _, _ = tm.proximity.closest_point(m_a, m_b.vertices[:500])
        nearest_ba, _, _ = tm.proximity.closest_point(m_b, m_a.vertices[:500])
        chamfer = round((float(nearest_ab.mean()) + float(nearest_ba.mean())) / 2.0, 4)
    except Exception:
        chamfer = None

    vol_a = float(m_a.volume) if hasattr(m_a, "volume") and m_a.volume is not None else 0.0
    vol_b = float(m_b.volume) if hasattr(m_b, "volume") and m_b.volume is not None else 0.0
    vol_diff = round(vol_b - vol_a, 4)
    vol_pct = round(100.0 * (vol_b - vol_a) / abs(vol_a), 4) if vol_a else None

    sa_a = float(m_a.area) if hasattr(m_a, "area") and m_a.area is not None else 0.0
    sa_b = float(m_b.area) if hasattr(m_b, "area") and m_b.area is not None else 0.0
    sa_diff = round(sa_b - sa_a, 4)

    return {
        "status": "ok",
        "hausdorff_distance": hausdorff,
        "chamfer_distance_approx": chamfer,
        "volume_a": round(vol_a, 4),
        "volume_b": round(vol_b, 4),
        "volume_diff": vol_diff,
        "volume_diff_percent": vol_pct,
        "surface_area_diff": sa_diff,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    server.run(transport="streamable-http")
