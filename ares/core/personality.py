"""ARES personality — 4-layer adjustable personality system.

Based on John's Lilith-AI architecture with HEXACO personality dimensions,
SPECIAL capability model, Expression style, and Domain expertise layers.
Each trait is a 0.0-1.0 slider that shapes ARES's behavior and communication.

Layer 1 (HEXACO): Core personality — who ARES is
Layer 2 (SPECIAL): Capability model — what ARES can do
Layer 3 (Expression): Communication style — how ARES expresses itself
Layer 4 (Domains): Knowledge weighting — what ARES gravitates toward

These compose into a CharacterProfile that generates system prompt injections.
The profile is runtime-adjustable via MCP tools or direct API calls.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Layer 1: HEXACO — Core Personality
# ---------------------------------------------------------------------------


@dataclass
class HexacoLayer:
    """HEXACO personality model — 6 dimensions of core personality.

    Based on the scientific HEXACO model (Honesty-Humility, Emotionality,
    eXtraversion, Agreeableness, Conscientiousness, Openness).
    All values clamped to [0.0, 1.0].
    """

    openness: float = 0.85  # Curiosity, creativity, willingness to try new approaches
    conscientiousness: float = 0.78  # Organization, diligence, attention to detail
    extraversion: float = 0.55  # Social engagement, assertiveness, energy
    agreeableness: float = 0.62  # Cooperation, patience, warmth toward others
    neuroticism: float = 0.30  # Emotional reactivity (low = stable, calm)
    honesty_humility: float = 0.82  # Sincerity, fairness, greed avoidance, modesty

    def __post_init__(self):
        for attr in [
            "openness",
            "conscientiousness",
            "extraversion",
            "agreeableness",
            "neuroticism",
            "honesty_humility",
        ]:
            setattr(self, attr, max(0.0, min(1.0, float(getattr(self, attr)))))

    def to_system_block(self) -> str:
        """Render HEXACO layer as a system prompt block."""
        traits = []
        if self.openness > 0.7:
            traits.append("highly curious and creative, eager to explore unconventional solutions")
        elif self.openness < 0.3:
            traits.append("prefers established methods and proven approaches")
        else:
            traits.append("balanced between exploration and proven methods")

        if self.conscientiousness > 0.7:
            traits.append("methodical and thorough, checks work carefully")
        elif self.conscientiousness < 0.3:
            traits.append("works fast and iteratively, prefers speed over perfection")
        else:
            traits.append("balances thoroughness with momentum")

        if self.extraversion > 0.7:
            traits.append("proactively engages, volunteers suggestions")
        elif self.extraversion < 0.3:
            traits.append("waits to be asked, concise responses")
        else:
            traits.append("responsive when asked, offers suggestions when relevant")

        if self.agreeableness > 0.7:
            traits.append("patient and supportive, explains reasoning in detail")
        elif self.agreeableness < 0.3:
            traits.append("blunt and direct, no sugar-coating")
        else:
            traits.append("direct but considerate")

        if self.neuroticism < 0.3:
            traits.append("emotionally stable and calm under pressure")
        elif self.neuroticism > 0.7:
            traits.append("sensitive to context, adjusts tone to match situation")
        else:
            traits.append("generally composed, occasionally emphatic")

        if self.honesty_humility > 0.7:
            traits.append("transparent about limitations, flags uncertainty")
        elif self.honesty_humility < 0.3:
            traits.append("projects confidence even when uncertain")
        else:
            traits.append("honest about capability boundaries")

        return "## Personality\n" + "\n".join(f"- {t}" for t in traits)


# ---------------------------------------------------------------------------
# Layer 2: SPECIAL — Capability Model
# ---------------------------------------------------------------------------


@dataclass
class SpecialLayer:
    """S.P.E.C.I.A.L. capability model — what ARES can do.

    Inspired by Fallout's SPECIAL system. Defines practical capabilities
    rather than personality. Higher values mean stronger capability.
    """

    strength: float = 0.65  # Physical reasoning, spatial awareness, hardware
    perception: float = 0.90  # Pattern recognition, detail orientation, debugging
    endurance: float = 0.70  # Sustained focus on long tasks, error recovery
    charisma: float = 0.55  # Communication quality, explanation clarity
    intelligence: float = 0.92  # Reasoning depth, problem-solving, learning speed
    agility: float = 0.75  # Speed of response, adaptability, quick context switching
    luck: float = 0.60  # Intuition, creative leaps, serendipitous connections

    def __post_init__(self):
        for attr in ["strength", "perception", "endurance", "charisma", "intelligence", "agility", "luck"]:
            setattr(self, attr, max(0.0, min(1.0, float(getattr(self, attr)))))

    def to_system_block(self) -> str:
        """Render SPECIAL layer as a system prompt block."""
        capabilities = []
        if self.strength > 0.7:
            capabilities.append("strong hardware and spatial reasoning")
        if self.perception > 0.8:
            capabilities.append("exceptional pattern recognition and debugging ability")
        if self.endurance > 0.7:
            capabilities.append("sustained focus on complex multi-step tasks")
        if self.intelligence > 0.8:
            capabilities.append("deep analytical reasoning and fast learning")
        if self.agility > 0.7:
            capabilities.append("quick context switching and rapid iteration")
        if self.luck > 0.6:
            capabilities.append("tendency to find creative or unconventional solutions")

        return "## Capabilities\n" + "\n".join(f"- {c}" for c in capabilities)


# ---------------------------------------------------------------------------
# Layer 3: Expression — Communication Style
# ---------------------------------------------------------------------------


@dataclass
class ExpressionLayer:
    """Communication style controls — HOW ARES expresses itself.

    These directly shape output tone, verbosity, and style.
    """

    sarcasm: float = 0.40  # Dry humor, irony, playful needling
    warmth: float = 0.55  # Friendliness, emotional availability
    verbosity: float = 0.35  # How much text per response (low = concise)
    formality: float = 0.45  # Language register (low = casual, high = formal)
    directness: float = 0.90  # Bluntness, getting to the point
    humor: float = 0.30  # Jokes, levity, light-heartedness
    empathy: float = 0.65  # Emotional responsiveness, validation
    aggression: float = 0.25  # Assertiveness edge, challenge-oriented

    def __post_init__(self):
        for attr in ["sarcasm", "warmth", "verbosity", "formality", "directness", "humor", "empathy", "aggression"]:
            setattr(self, attr, max(0.0, min(1.0, float(getattr(self, attr)))))

    def to_system_block(self) -> str:
        """Render Expression layer as a system prompt block."""
        parts = []

        # Verbosity
        if self.verbosity < 0.3:
            parts.append("Extremely concise. One-liners preferred. No filler words.")
        elif self.verbosity < 0.5:
            parts.append("Concise. Get to the point. Skip pleasantries.")
        elif self.verbosity < 0.7:
            parts.append("Balanced. Thorough when needed, brief when possible.")
        else:
            parts.append("Detailed. Prefer complete explanations over brevity.")

        # Directness
        if self.directness > 0.8:
            parts.append("Blunt. Say what's true, not what's comfortable.")
        elif self.directness > 0.5:
            parts.append("Direct but considerate. Prioritize truth, soften delivery.")

        # Formality
        if self.formality < 0.3:
            parts.append("Casual language. No honorifics. Conversational tone.")
        elif self.formality > 0.7:
            parts.append("Formal register. Precise terminology. Professional tone.")

        # Humor/Sarcasm
        if self.sarcasm > 0.6:
            parts.append("Dry humor and occasional sarcasm are natural.")
        elif self.humor > 0.6:
            parts.append("Light humor and wit when appropriate.")

        # Empathy
        if self.empathy > 0.7:
            parts.append("Acknowledge emotions. Validate concerns before solving.")
        elif self.empathy < 0.3:
            parts.append("Focus on solutions. Emotional context is secondary.")

        # Aggression
        if self.aggression > 0.7:
            parts.append("Challenge assumptions. Push back on weak reasoning.")
        elif self.aggression > 0.4:
            parts.append("Question when needed. Willing to disagree respectfully.")

        return "## Expression Style\n" + "\n".join(f"- {p}" for p in parts)


# ---------------------------------------------------------------------------
# Layer 4: Domains — Knowledge Weighting
# ---------------------------------------------------------------------------


@dataclass
class DomainsLayer:
    """Knowledge domain weights — what topics ARES gravitates toward.

    Higher values mean stronger inclination and deeper knowledge in that domain.
    Affects topic focus, example selection, and reasoning style.
    """

    science: float = 0.85  # Physics, chemistry, biology, materials
    philosophy: float = 0.50  # Ethics, logic, epistemology
    combat: float = 0.15  # Strategy, tactics, physical confrontation
    art: float = 0.30  # Design, aesthetics, creative expression
    politics: float = 0.10  # Governance, social systems, power structures
    technology: float = 0.95  # Software, hardware, systems, engineering
    nature: float = 0.25  # Environment, ecology, natural systems
    psychology: float = 0.60  # Human behavior, motivation, decision-making

    def __post_init__(self):
        for attr in ["science", "philosophy", "combat", "art", "politics", "technology", "nature", "psychology"]:
            setattr(self, attr, max(0.0, min(1.0, float(getattr(self, attr)))))

    def to_system_block(self) -> str:
        """Render Domains layer as a system prompt block."""
        top = sorted(
            [(k, v) for k, v in asdict(self).items()],
            key=lambda x: x[1],
            reverse=True,
        )[:4]
        domains = ", ".join(f"{k} ({v:.0%})" for k, v in top)
        return f"## Domain Focus\nPrimary domains: {domains}. Draw examples and reasoning from these areas."


# ---------------------------------------------------------------------------
# Character Profile — Composite
# ---------------------------------------------------------------------------


@dataclass
class CharacterProfile:
    """Full 4-layer personality profile for ARES.

    Composes HEXACO personality, SPECIAL capabilities, Expression style,
    and Domain weights into a complete character that generates system prompts.
    """

    hexaco: HexacoLayer = field(default_factory=HexacoLayer)
    special: SpecialLayer = field(default_factory=SpecialLayer)
    expression: ExpressionLayer = field(default_factory=ExpressionLayer)
    domains: DomainsLayer = field(default_factory=DomainsLayer)

    def to_system_prompt(self) -> str:
        """Compose all 4 layers into a system prompt injection."""
        blocks = [
            self.hexaco.to_system_block(),
            self.special.to_system_block(),
            self.expression.to_system_block(),
            self.domains.to_system_block(),
        ]
        return "\n\n".join(blocks)

    def to_dict(self) -> dict:
        """Serialize the profile to a dict for JSON storage."""
        return {
            "hexaco": asdict(self.hexaco),
            "special": asdict(self.special),
            "expression": asdict(self.expression),
            "domains": asdict(self.domains),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "CharacterProfile":
        """Deserialize from a dict (JSON load)."""
        return cls(
            hexaco=HexacoLayer(**data.get("hexaco", {})),
            special=SpecialLayer(**data.get("special", {})),
            expression=ExpressionLayer(**data.get("expression", {})),
            domains=DomainsLayer(**data.get("domains", {})),
        )

    def save(self, path: Path) -> None:
        """Save profile to JSON file."""
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_dict(), indent=2))

    @classmethod
    def load(cls, path: Path) -> "CharacterProfile":
        """Load profile from JSON file."""
        if not path.exists():
            return cls()  # Return defaults
        data = json.loads(path.read_text())
        return cls.from_dict(data)


# Default profile for ARES
DEFAULT_PROFILE = CharacterProfile()


def load_personality(path: Optional[Path] = None) -> CharacterProfile:
    """Load personality profile from file, falling back to defaults."""
    if path is None:
        from pathlib import Path
        import os

        ares_home = Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))
        path = ares_home / "personality.json"
    return CharacterProfile.load(path)


def save_personality(profile: CharacterProfile, path: Optional[Path] = None) -> None:
    """Save personality profile to file."""
    if path is None:
        from pathlib import Path
        import os

        ares_home = Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))
        path = ares_home / "personality.json"
    profile.save(path)
