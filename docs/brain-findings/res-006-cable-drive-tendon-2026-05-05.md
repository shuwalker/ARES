# RES-006: Cable-Drive / Tendon Transmission for 3D-Printed Robot Joints

**Date:** 2026-05-05 (Cycle 004)
**Status:** Research completed

## arXiv Search

arXiv search for "tendon-driven hand open source" returned 6 highly relevant papers. This is an active, well-published research area.

### Key Papers

| Paper | ID | Year | Relevance | Key Feature |
|-------|-----|------|-----------|-------------|
| **MM-Hand** | 2604.17245 | 2026 | ★★★★☆ | 21-DOF, remote actuation (motors in forearm), multi-modal sensing |
| **Ruka-v2** | 2603.26660 | 2026 | ★★★★★ | Open-source tendon-driven dexterous hand with wrist + abduction. Successor to Ruka (2504.13165). |
| **ORCA** | 2504.04259 | 2025 | ★★★★☆ | Open-source, reliable, cost-effective anthropomorphic hand for dexterous manipulation |
| **Tactile SoftHand-A** | 2406.12731 | 2024 | ★★★☆☆ | 3D-printed, tactile, highly underactuated, tendon-driven |
| **BRL/Pisa/IIT SoftHand** | 2206.12655 | 2022 | ★★★★★ | SINGLE actuator tendon-driven hand. 3D-printed, underactuated, adaptive grasping |

### The BRL/Pisa/IIT SoftHand is the Most DIY-Relevant

- **Single actuator** drives all 5 fingers via tendon routing
- Underactuation = fingers adapt to object shape automatically
- 3D-printed, low-cost
- This is the architecture pattern: one motor → tendon tree → multiple joints

### Ruka-v2 — Open Source Character Hand
- Most recent (2026), explicitly open-source
- Tendon-driven with wrist and abduction DOF
- Designed for robot learning research
- If Matthew wants a reference implementation, this is it

## Cable/Tendon Types for DIY

| Type | Strength | Friction | Stretch | Cost | DIY Notes |
|------|----------|----------|---------|------|-----------|
| **Dyneema/Spectra fishing line** | ★★★☆☆ | ★★★★★ | ★★★★★ | $0.10/ft | Best for small fingers. Near-zero stretch. Slippery — needs good crimping. |
| **Braided steel cable (0.5-1mm)** | ★★★★★ | ★★★☆☆ | ★★★★★ | $0.30/ft | For load-bearing joints. Needs crimp ferrules and cable cutters. |
| **Kevlar thread** | ★★★☆☆ | ★★★☆☆ | ★★★★★ | $0.15/ft | Good for flexure joints. Doesn't slip as much as Dyneema. |
| **Bowden cable (bike brake)** | ★★★★☆ | ★★☆☆☆ | ★★★★☆ | $2/ft | Pre-made with housing. Good for remote actuation. High friction. |
| **Nylon monofilament** | ★★☆☆☆ | ★★★★☆ | ★☆☆☆☆ | $0.02/ft | Stretches over time. Only for prototypes. |

## Routing Architectures

### 1. Direct tendon (ETH Hand pattern)
- Motor pulley → tendon → joint pulley → spring return
- Simplest. 1:1 or 1:2 ratio. Good for small joints.

### 2. Underactuated (SoftHand pattern)
- One motor → distribution pulley → multiple finger tendons
- Differential mechanism lets fingers adapt to object shape
- Reduces motor count dramatically

### 3. Capstan drive
- Motor shaft wrapped with multiple turns of cable
- No pulley needed — friction grip
- Best for compact designs
- Needs careful tension management

### 4. Bowden cable (MM-Hand pattern)
- Motor in forearm → Bowden housing → joint at wrist/finger
- Keeps mass out of the hand
- Friction penalty but enables remote actuation

## Key Insight for JP01

The tendon-driven approach is NOT just for hands. For a character robot:

1. **Shoulder/elbow:** Use BLDC+FOC direct drive OR belt reduction (not tendon). These need torque, not remote actuation.
2. **Wrist:** Tendon-driven from forearm via Bowden cable. Keeps arm mass low, wrist compact.
3. **Fingers:** Dyneema tendons, underactuated design (1-2 motors per hand).
4. **Face/expressive:** Small Bowden cables from a central actuator pack in the chest/head.

The ETH hand paper's 1:2 pulley routing for displacement amplification is the most elegant pattern — use a small motor with a 2:1 pulley to double the range of motion at the joint.

## Recommendations for JP01

| Joint | Transmission | Motor Location | Cable Type |
|-------|-------------|----------------|------------|
| Shoulder pitch | Belt reduction (3D printed) | In shoulder | N/A (belt) |
| Shoulder roll | Direct drive | In shoulder | N/A |
| Elbow | Belt reduction | Upper arm | N/A |
| Wrist pitch/roll | Bowden cable | Forearm | Dyneema or steel |
| Finger flex | Underactuated tendon | Forearm | Dyneema 0.3mm |
| Facial (brow, lip) | Bowden cable | Head/chest pack | Dyneema 0.2mm |

## Next Questions
- What's the lifespan of Dyneema tendons in a 3D-printed pulley system (abrasion)?
- Can we print compliant joints (flexures) that eliminate bearings for small DOF?
- What's the minimum number of actuators for an expressive face (eyes + brows + mouth)?
