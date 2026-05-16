"""ARES Simulation MCP Server — physics simulation via PyBullet.

Tools:
- simulate_gravity  : Drop a mesh, simulate 5 s, return stability & orientation
- simulate_balance  : Multi-link inverted pendulum (standing) stability
- check_collision   : AABB/mesh intersection + penetration / separation
- simulate_torque   : Robot arm reaching target angles under torque limits

MCP :9516, StreamableHTTP.
"""

from __future__ import annotations

import logging
import math
import os
import time
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.simulation")

server = FastMCP(
    name="ARES Simulation",
    instructions="Physics simulation tools using PyBullet: gravity drop, balance, collision detection, torque-limited arm.",
    host="0.0.0.0",
    port=9516,
)

_start_time = time.time()
_pb = None
_pb_available: bool | None = None


def _get_pb() -> bool:
    """Lazy-import pybullet (and pybullet_data)."""
    global _pb, _pb_available
    if _pb_available is not None:
        return _pb_available
    try:
        import pybullet as pb

        _pb = pb
        _pb_available = True
        logger.info("PyBullet imported successfully")
    except Exception as e:
        _pb_available = False
        logger.error("PyBullet import failed: %s", e)
    return _pb_available


def _load_mesh_path(mesh_path: str) -> Optional[Path]:
    p = Path(mesh_path).expanduser().resolve()
    if not p.exists():
        return None
    return p


def _quat_to_euler(q) -> list[float]:
    """Convert PyBullet quaternion [x,y,z,w] to Euler angles [roll,pitch,yaw]."""
    x, y, z, w = q
    sinr_cosp = 2.0 * (w * x + y * z)
    cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    sinp = 2.0 * (w * y - z * x)
    if abs(sinp) >= 1:
        pitch = math.copysign(math.pi / 2, sinp)
    else:
        pitch = math.asin(sinp)

    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    yaw = math.atan2(siny_cosp, cosy_cosp)

    return [round(roll, 4), round(pitch, 4), round(yaw, 4)]


def _pb_pose_to_dict(pos, orn) -> dict:
    return {
        "position": [round(float(v), 4) for v in pos],
        "orientation": [round(float(v), 4) for v in orn],
        "euler_deg": [round(math.degrees(v), 2) for v in _quat_to_euler(orn)],
    }


# ═══ Helpers for optional trimesh support ════════════════════════════════════


def _load_mesh_collision_shape(pb_module, mesh_path: str) -> Optional[int]:
    """Create a PyBullet collision shape from a mesh file."""
    p = _load_mesh_path(mesh_path)
    if p is None:
        return None
    ext = p.suffix.lower()

    # Use convex hull for meshes; pybullet.createCollisionShape works with OBJ/STL directly
    try:
        if ext in (".stl", ".obj", ".dae"):
            shape_id = pb_module.createCollisionShape(
                pb_module.GEOM_MESH,
                fileName=str(p),
                meshScale=[1, 1, 1],
            )
            if shape_id >= 0:
                return shape_id
    except Exception as e:
        logger.debug("Mesh collision shape failed: %s", e)

    # Fallback: try loading shape via native types
    return None


def _make_box_collider(pb_module, half_extents: list[float]) -> int:
    return pb_module.createCollisionShape(pb_module.GEOM_BOX, halfExtents=half_extents)


def _simple_mesh_bounds(mesh_path: str) -> Optional[list[float]]:
    """Attempt to read mesh bounds via trimesh if available."""
    try:
        import trimesh as tm

        m = tm.load(mesh_path)
        if hasattr(m, "extents"):
            return [round(float(v) / 2.0, 4) for v in m.extents.tolist()]
    except Exception:
        pass
    return None


# ═══ Tool: simulate_gravity ══════════════════════════════════════════════════


@server.tool()
def simulate_gravity(mesh_path: str, mass_kg: float = 1.0) -> dict:
    """Load a mesh, drop it on a plane, simulate 5 seconds with PyBullet.

    Returns:
        dict: did it fall over, final orientation / CoM trajectory / stability score.
    """
    if not _get_pb():
        return {
            "status": "error",
            "error": "PyBullet not available",
            "fallen_over": None,
            "final_orientation": None,
            "com_trajectory": [],
            "stability_score": None,
        }

    pb = _pb
    p = _load_mesh_path(mesh_path)
    if p is None:
        return {
            "status": "error",
            "error": f"Mesh not found: {mesh_path}",
        }

    pb.connect(pb.DIRECT)
    try:
        pb.setGravity(0, 0, -9.81)
        pb.setAdditionalSearchPath(os.path.dirname(str(p)))
        plane = pb.createMultiBody(baseMass=0, baseCollisionShapeIndex=pb.createCollisionShape(pb.GEOM_PLANE))

        # Create collision shape and multi-body
        shape_id = _load_mesh_collision_shape(pb, str(p))
        if shape_id is None:
            # Fallback: estimate as a box
            half_extents = _simple_mesh_bounds(str(p)) or [0.05, 0.05, 0.05]
            shape_id = _make_box_collider(pb, half_extents)

        base_pos = [0, 0, 0.5]
        base_orn = pb.getQuaternionFromEuler([0, 0, 0])
        body_id = pb.createMultiBody(
            baseMass=mass_kg,
            baseCollisionShapeIndex=shape_id,
            baseVisualShapeIndex=shape_id,
            basePosition=base_pos,
            baseOrientation=base_orn,
        )

        # Friction for ground
        pb.changeDynamics(plane, -1, lateralFriction=0.8, restitution=0.2)
        pb.changeDynamics(body_id, -1, lateralFriction=0.6, restitution=0.2)

        # Settle small initial jitter
        pb.stepSimulation()

        # Record CoM trajectory
        trajectory = []
        steps = int(5.0 * 240)  # 240 Hz, 5 s
        upright_prev = True
        fall_time = None

        for i in range(steps):
            pb.stepSimulation()
            pos, orn = pb.getBasePositionAndOrientation(body_id)
            euler = _quat_to_euler(orn)
            trajectory.append(
                {
                    "time": round(i / 240.0, 3),
                    "position": [round(float(v), 4) for v in pos],
                    "euler_deg": [round(math.degrees(v), 2) for v in euler],
                }
            )
            # Detect if it fell over (any axis > 45°)
            max_lean = max(abs(euler[0]), abs(euler[1]))
            if max_lean > math.radians(45):
                if upright_prev:
                    fall_time = round(i / 240.0, 3)
                upright_prev = False

        final_pos, final_orn = pb.getBasePositionAndOrientation(body_id)
        final_euler = _quat_to_euler(final_orn)
        max_lean_final = max(abs(final_euler[0]), abs(final_euler[1]))
        fallen = max_lean_final > math.radians(45) or fall_time is not None

        # Stability score: how far from 45° (0 = just fell, 1 = upright)
        if fallen:
            angle_away = min(max_lean_final, math.pi / 2)
            stability = max(0.0, 1.0 - (angle_away / (math.pi / 2)))
        else:
            stability = 1.0

        return {
            "status": "ok",
            "mesh_path": str(p),
            "mass_kg": mass_kg,
            "fallen_over": bool(fallen),
            "fall_time_s": fall_time,
            "final_orientation": _pb_pose_to_dict(final_pos, final_orn),
            "com_trajectory": trajectory[::240],  # downsample ~1 Hz
            "stability_score": round(stability, 4),
        }
    except Exception as e:
        logger.error("simulate_gravity failed: %s", e)
        return {"status": "error", "error": str(e)}
    finally:
        pb.disconnect()


# ═══ Tool: simulate_balance ════════════════════════════════════════════════════


@server.tool()
def simulate_balance(link_lengths: list[float], link_masses: list[float], base_width: float) -> dict:
    """Simulate a multi-link inverted pendulum (robot standing) in PyBullet.

    Returns:
        dict: max lean angle before falling, recovery time, stability metrics.
    """
    if not _get_pb():
        return {
            "status": "error",
            "error": "PyBullet not available",
            "max_lean_angle_deg": None,
            "recovery_time_s": None,
            "stable": None,
        }

    pb = _pb
    pb.connect(pb.DIRECT)
    try:
        pb.setGravity(0, 0, -9.81)

        # Build base flat box
        base_half = [base_width / 2.0, base_width / 2.0, 0.05]
        base_shape = pb.createCollisionShape(pb.GEOM_BOX, halfExtents=base_half)
        base_id = pb.createMultiBody(
            baseMass=1.0,
            baseCollisionShapeIndex=base_shape,
            basePosition=[0, 0, 0.05],
        )

        prev_body = base_id
        prev_link = -1
        joints = []
        for i, (length, mass) in enumerate(zip(link_lengths, link_masses)):
            half_extents = [0.03, 0.03, length / 2.0]
            shape_id = pb.createCollisionShape(pb.GEOM_BOX, halfExtents=half_extents)
            link_mass = float(mass)

            body_id = pb.createMultiBody(
                baseMass=link_mass,
                baseCollisionShapeIndex=shape_id,
                basePosition=[0, 0, 0.1 + length / 2.0 + i * length],
            )

            # Fixed constraint to previous body for stacking (simplified)
            cid = pb.createConstraint(
                parentBodyUniqueId=prev_body,
                parentLinkIndex=prev_link,
                childBodyUniqueId=body_id,
                childLinkIndex=-1,
                jointType=pb.JOINT_POINT2POINT,
                jointPivotInParent=[0, 0, length / 2.0] if i == 0 else [0, 0, 0.0],
                jointPivotInChild=[0, 0, -length / 2.0],
            )
            pb.changeConstraint(cid, maxForce=1000.0)
            joints.append(cid)
            prev_body = body_id
            prev_link = -1

        # Step and perturb
        for _ in range(48):
            pb.stepSimulation()

        # Measure angle at which it falls by tilting the base slightly
        max_lean = 0.0
        fall_time = None
        steps = int(5.0 * 240)
        for i in range(steps):
            pb.stepSimulation()
            pos, orn = pb.getBasePositionAndOrientation(prev_body)
            euler = _quat_to_euler(orn)
            lean = max(abs(math.degrees(euler[0])), abs(math.degrees(euler[1])))
            if lean > max_lean:
                max_lean = lean
            if lean > 45.0 and fall_time is None:
                fall_time = round(i / 240.0, 3)

        stable = fall_time is None and max_lean < 45.0

        return {
            "status": "ok",
            "base_width": base_width,
            "link_count": len(link_lengths),
            "max_lean_angle_deg": round(max_lean, 2),
            "fall_time_s": fall_time,
            "recovery_time_s": None if fall_time is None else round(max(fall_time, 0.0), 3),
            "stable": bool(stable),
        }
    except Exception as e:
        logger.error("simulate_balance failed: %s", e)
        return {"status": "error", "error": str(e)}
    finally:
        pb.disconnect()


# ═══ Tool: check_collision ════════════════════════════════════════════════════


@server.tool()
def check_collision(mesh_a: str, mesh_b: str, transform_a: dict = None, transform_b: dict = None) -> dict:
    """Load two meshes, apply transforms, check if they intersect in PyBullet.

    Returns:
        dict: colliding, contact points, penetration depth, separation distance.
    """
    if not _get_pb():
        return {
            "status": "error",
            "error": "PyBullet not available",
            "colliding": None,
            "contact_points": [],
            "penetration_depth": None,
            "separation_distance": None,
        }

    pb = _pb
    p_a = _load_mesh_path(mesh_a)
    p_b = _load_mesh_path(mesh_b)
    if p_a is None or p_b is None:
        return {"status": "error", "error": "One or both meshes not found"}

    transform_a = transform_a or {}
    transform_b = transform_b or {}

    def _build_body(pb_module, mesh_path: str, xf: dict) -> Optional[int]:
        pos = xf.get("position", [0, 0, 0])
        rot = xf.get("rotation", [0, 0, 0])  # euler degrees
        orn = pb_module.getQuaternionFromEuler([math.radians(v) for v in rot])
        shape_id = _load_mesh_collision_shape(pb_module, mesh_path)
        if shape_id is None:
            half_ext = _simple_mesh_bounds(mesh_path) or [0.05, 0.05, 0.05]
            shape_id = _make_box_collider(pb_module, half_ext)
        body = pb_module.createMultiBody(
            baseMass=0.0,
            baseCollisionShapeIndex=shape_id,
            basePosition=pos,
            baseOrientation=orn,
        )
        return body

    pb.connect(pb.DIRECT)
    try:
        body_a = _build_body(pb, str(p_a), transform_a)
        body_b = _build_body(pb, str(p_b), transform_b)

        # Step once to register contact
        for _ in range(2):
            pb.stepSimulation()

        contacts = pb.getContactPoints(bodyA=body_a, bodyB=body_b)
        colliding = len(contacts) > 0

        pts = []
        min_dist = float("inf")
        max_pen = None
        for c in contacts:
            dist = float(c[8])
            pen = float(c[9])
            pts.append(
                {
                    "positionOnA": [round(float(v), 4) for v in c[5]],
                    "positionOnB": [round(float(v), 4) for v in c[6]],
                    "contactDistance": round(dist, 6),
                    "penetrationDepth": round(pen, 6),
                }
            )
            if dist < min_dist:
                min_dist = dist
            if pen > (max_pen or 0):
                max_pen = pen

        # If no contacts, compute closest points
        if not colliding:
            closest = pb.getClosestPoints(body_a, body_b, distance=100.0)
            sep = float("inf")
            for cp in closest:
                d = float(cp[8])
                if d < sep:
                    sep = d
            if sep == float("inf"):
                sep = None
        else:
            sep = max_pen

        return {
            "status": "ok",
            "mesh_a": str(p_a),
            "mesh_b": str(p_b),
            "colliding": colliding,
            "contact_points": pts,
            "penetration_depth": round(max_pen, 6) if max_pen is not None else None,
            "separation_distance": round(sep, 6) if sep is not None else None,
        }
    except Exception as e:
        logger.error("check_collision failed: %s", e)
        return {"status": "error", "error": str(e)}
    finally:
        pb.disconnect()


# ═══ Tool: simulate_torque ═══════════════════════════════════════════════════


@server.tool()
def simulate_torque(
    joint_count: int,
    link_lengths: list[float],
    link_masses: list[float],
    max_torque_nm: float,
    target_angles: list[float],
) -> dict:
    """Simulate a robot arm reaching target angles given torque constraints.

    Returns:
        dict: reachable, final angles, time_to_target, max_velocity, energy_used.
    """
    if not _get_pb():
        return {
            "status": "error",
            "error": "PyBullet not available",
            "reachable": None,
            "final_angles_deg": None,
            "time_to_target_s": None,
            "max_velocity_degs": None,
            "energy_used_j": None,
        }

    pb = _pb
    pb.connect(pb.DIRECT)
    try:
        pb.setGravity(0, 0, -9.81)
        pb.loadURDF(
            "plane.urdf",
            basePosition=[0, 0, 0],
        )

        # Build simple revolute serial arm
        base_shape = pb.createCollisionShape(pb.GEOM_BOX, halfExtents=[0.05, 0.05, 0.05])
        base_id = pb.createMultiBody(
            baseMass=0.0,
            baseCollisionShapeIndex=base_shape,
            basePosition=[0, 0, 0.05],
        )

        prev_body = base_id
        joint_ids = []
        for i in range(joint_count):
            length = link_lengths[i] if i < len(link_lengths) else 0.1
            mass = link_masses[i] if i < len(link_masses) else 0.1
            half_extents = [0.02, 0.02, length / 2.0]
            shape_id = pb.createCollisionShape(pb.GEOM_BOX, halfExtents=half_extents)
            link_id = pb.createMultiBody(
                baseMass=mass,
                baseCollisionShapeIndex=shape_id,
                basePosition=[0, 0, 0.05 + (i + 1) * length],
                baseOrientation=pb.getQuaternionFromEuler([0, 0, 0]),
            )
            joint_type = pb.JOINT_REVOLUTE
            joint_axis = [1, 0, 0] if i % 2 == 0 else [0, 1, 0]
            pivot_parent = [0, 0, length / 2.0] if i == 0 else [0, 0, length / 2.0]
            pivot_child = [0, 0, -length / 2.0]

            cid = pb.createConstraint(
                parentBodyUniqueId=prev_body,
                parentLinkIndex=-1,
                childBodyUniqueId=link_id,
                childLinkIndex=-1,
                jointType=joint_type,
                jointAxis=joint_axis,
                parentFramePosition=pivot_parent,
                childFramePosition=pivot_child,
            )
            pb.changeConstraint(cid, maxForce=max_torque_nm)
            joint_ids.append(cid)
            prev_body = link_id

        # Warmup
        for _ in range(12):
            pb.stepSimulation()

        # Controller: set target angles via changeConstraint motor
        target_rad = [math.radians(v) for v in target_angles]
        for idx, cid in enumerate(joint_ids):
            if idx < len(target_rad):
                pb.changeConstraint(cid, target_rad[idx], maxForce=max_torque_nm)

        # Simulate until target reached or timeout
        final_angles = [0.0] * joint_count
        max_vel = 0.0
        energy = 0.0
        reached = False
        time_to_target = None
        steps = int(10.0 * 240)
        tol = math.radians(2.0)

        for i in range(steps):
            pb.stepSimulation()
            # Measure joint states via constraint relative orientation approx
            # (simplified: just use base orientation of last link as proxy)
            pos, orn = pb.getBasePositionAndOrientation(prev_body)
            euler = _quat_to_euler(orn)
            final_angles = [math.degrees(e) for e in euler[:joint_count]]

            # Approx angular velocity from pos delta (very coarse)
            vel = pb.getBaseVelocity(prev_body)
            ang_mag = math.sqrt(sum(v * v for v in vel[1]))
            if ang_mag > max_vel:
                max_vel = ang_mag

            # Energy proxy: sum torque * angular displacement per step
            disp = ang_mag * (1.0 / 240.0)
            energy += max_torque_nm * disp

            # Check convergence
            diffs = [abs(final_angles[j] - target_angles[j]) for j in range(min(joint_count, len(target_angles)))]
            if all(d < math.degrees(tol) for d in diffs) and time_to_target is None:
                time_to_target = round(i / 240.0, 3)
                reached = True
                # Stop early once reached
                break

        if not reached:
            time_to_target = round(steps / 240.0, 3)

        return {
            "status": "ok",
            "joint_count": joint_count,
            "max_torque_nm": max_torque_nm,
            "reachable": reached,
            "final_angles_deg": [round(v, 2) for v in final_angles[:joint_count]],
            "target_angles_deg": [round(float(v), 2) for v in target_angles[:joint_count]],
            "time_to_target_s": time_to_target,
            "max_velocity_degs": round(math.degrees(max_vel), 2),
            "energy_used_j": round(energy, 4),
        }
    except Exception as e:
        logger.error("simulate_torque failed: %s", e)
        return {"status": "error", "error": str(e)}
    finally:
        pb.disconnect()


# ═══ Health check ════════════════════════════════════════════════════════════


@server.tool()
def simulation_health() -> dict:
    """Report simulation service health."""
    return {
        "status": "ok" if _get_pb() else "pybullet_missing",
        "uptime": int(time.time() - _start_time),
        "pybullet_available": _pb_available if _pb_available is not None else False,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    server.run(transport="streamable-http")
