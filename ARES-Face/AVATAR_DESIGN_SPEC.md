# ARES Avatar Design Specification

## Reference Videos
1. **P1esMBRqXAA** — PRIMARY avatar style (cyberpunk anime girl with glowing slit eyes)
2. **f_1DYoTkFlY** — Secondary character style (high-fidelity cel-shaded anime, Attack on Titan aesthetic)
3. **BHywIsHCNx8** — Environment/mood reference (mystical stone architecture, Kabbalistic imagery, solemn voids)

---

## Avatar #1: "Synth Muse" (Primary — from video 1)

### Face Design (Metal Shader Spec)

**Eyes:**
- Stylized anime eyes, NOT round pupils
- When closed: dark curved slits with thick black eyeliner tapering to points
- When open: glowing magenta/pink apertures — light emanates FROM WITHIN, no visible pupil
- Bright sparkle highlights at upper-left of each eye
- Expression state drives: neutral (open slits), happy (closed crescents), surprised (wider rounder), sleepy (half-narrowed)

**Face Markings (The "Stripes"):**
- THREE parallel diagonal slashes on ONE cheek (right cheek / viewer's left)
- ~45° angle, running from cheekbone toward jawline
- Flat near-black, sharp edges, no blur/gradient
- These are the avatar's "circuitry ports" — synthetic identity markers

**Skin Rendering:**
- 3-step cel shading (NOT smooth gradient):
  - Base tone: pale lavender/pink (#E0C3FC)
  - Shadow tone: muted purple (#B19CD9)
  - Highlight/rim light: electric cyan (#7DF9FF)
- Hard edges between light/shadow zones (step function)
- Rim light on silhouette edges (neon bloom bleeding from background)

**Hair:**
- Chin-length bob, blunt-cut bangs covering forehead
- Base: deep midnight blue/black (#0A0A23)
- Cyan/blue rim light on outer silhouette
- Purple sheen on top surface from ambient environment
- Rendered as solid clumps, not individual strands

**Mouth/Nose:**
- Mouth: thin curved black line (no detailed lips)
- Nose: minimal — just a subtle shadow line on one side
- When speaking: mouth animates as a wider curved line with open/close

**Accessories:**
- Bright pink/magenta heart-shaped earrings (#FF00FF)
- Black choker/collar at neck

**Color Palette:**
| Element | Hex | Description |
|---------|-----|-------------|
| Skin Base | #E0C3FC | Pale lavender |
| Skin Shadow | #B19CD9 | Muted purple |
| Rim Light | #7DF9FF | Electric cyan |
| Hair Base | #0A0A23 | Deep midnight blue |
| Eye Glow | #FF00FF | Magenta/pink |
| Markings | #1A1A1A | Near-black |
| Earring | #FF00FF | Hot pink |
| Choker | #1A1A1A | Near-black |

---

## Avatar #2: "Warrior Sage" (from video 2)

### Face Design

**Eyes:**
- Narrow, sharp, focused — small pupils
- Set deep under heavy angular brow
- Determined/stern expression
- Yellow/golden iris color when visible

**Face:**
- Thick blonde beard/mustache rendered with linear strokes
- Strong angular jawline
- Prominent nose

**Style:**
- High-fidelity cel-shaded anime (Guilty Gear Strive / Fate quality)
- Hard-edge shadows with soft atmospheric gradients
- Thin consistent line weight
- Muted cool palette: desaturated blues, slate greys, pale gold hair

**Hair:**
- Long pale blonde, tied back
- Solid color blocks, not individual strands

**Clothing:**
- White/off-white draped robe or kimono
- Loose-fitting, ceremonial

---

## Environment Style (from video 3)

### Mood: "Mystic Void"
- Massive monolithic stone architecture — towering walls creating canyon-like streets
- Floating stone tablets with Kabbalistic/Sephiroth inscriptions
- Radial sunburst patterns behind key moments
- Muted, desaturated cool tones: greys, charcoals, slate
- Characters pop with bright accents (yellow hair, teal jackets) against the monochrome environment
- Diffused, atmospheric lighting — no single hard light source
- Occult/sacred geometry motifs (circles, radiating lines, Hebrew-derived text)
- Scale contrast: small figures against immense architecture

### For ARES Environments:
- NOT neon/cyberpunk backgrounds for the environment
- Instead: sombre, sacred, immense stone halls and void spaces
- The avatar floats/presents against these backgrounds
- The contrast: synthetic neon avatar WITHIN ancient mystical spaces
- This juxtaposition (high-tech face, ancient-mystic place) is the identity

---

## ARES Avatar System — Combined Design Language

The ARES avatar system should MERGE these references:

1. **The Face**: Cyberpunk synth-muse style — cel-shaded with glowing slit eyes and cheek stripes
2. **The Secondary Character**: Could be an alternate avatar/ companion — warrior sage
3. **The Environment**: Mystic void with sacred geometry — NOT neon cityscapes

The ARES identity: **a synthetic entity standing in ancient sacred spaces.**
Neon body, stone cathedral. Technology meets mysticism.

All rendered real-time on-device via Metal shaders on Apple Silicon.