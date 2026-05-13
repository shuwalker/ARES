import json
import os
import datetime
from dataclasses import dataclass, field, asdict

# --- SECTION 1: DATACLASSES ---

@dataclass
class HexacoLayer:
    """Big Five + Honesty-Humility (HEXACO model)
    Scientific personality foundation."""
    openness: float = 0.5          # imagination, curiosity, new experiences
    conscientiousness: float = 0.5 # organization, discipline, impulse control
    extraversion: float = 0.5      # sociability, energy, assertiveness
    agreeableness: float = 0.5     # trust, kindness, cooperation
    neuroticism: float = 0.5       # emotional instability, anxiety, moodiness
    honesty_humility: float = 0.8  # sincerity, fairness, modesty

    def __post_init__(self):
        for k, v in self.__dict__.items():
            setattr(self, k, max(0.0, min(1.0, float(v))))

@dataclass
class SpecialLayer:
    """Fallout S.P.E.C.I.A.L. capability model.
    Defines what the character CAN DO, not just who they are."""
    strength: float = 0.5     # forcefulness, conviction, physical presence
    perception: float = 0.5   # awareness, attention to detail, intuition
    endurance: float = 0.5    # patience, resilience, persistence
    charisma: float = 0.5     # charm, persuasion, social magnetism
    intelligence: float = 0.5 # reasoning, knowledge, problem solving
    agility: float = 0.5      # adaptability, quick thinking, flexibility
    luck: float = 0.5         # optimism, serendipity, risk tolerance

    def __post_init__(self):
        for k, v in self.__dict__.items():
            setattr(self, k, max(0.0, min(1.0, float(v))))

@dataclass
class ExpressionLayer:
    """Communication style — HOW the character expresses themselves.
    Preserves all original Lilith traits."""
    sarcasm: float = 0.2    # irony and wit vs sincerity
    warmth: float = 0.5     # friendliness and approachability
    verbosity: float = 0.5  # concise vs elaborate responses
    formality: float = 0.5  # casual vs professional register
    directness: float = 0.7 # blunt vs diplomatic
    humor: float = 0.3      # playfulness and levity
    empathy: float = 0.4    # emotional mirroring and compassion
    aggression: float = 0.3 # confrontational vs passive

    def __post_init__(self):
        for k, v in self.__dict__.items():
            setattr(self, k, max(0.0, min(1.0, float(v))))

@dataclass
class DomainsLayer:
    """Knowledge domain interest and expertise weights.
    Affects what topics the character gravitates toward."""
    science: float = 0.5
    philosophy: float = 0.5
    combat: float = 0.5
    art: float = 0.5
    politics: float = 0.5
    technology: float = 0.5
    nature: float = 0.5
    psychology: float = 0.5

    def __post_init__(self):
        for k, v in self.__dict__.items():
            setattr(self, k, max(0.0, min(1.0, float(v))))

@dataclass
class MoodState:
    """Dynamic mood — changes during conversation, decays to neutral.
    NOT saved to character files (runtime only)."""
    current_emotion: str = "neutral"
    intensity: float = 0.0
    decay_rate: float = 0.1   # how fast mood returns to neutral per message
    trigger_history: list = field(default_factory=list)  # last 5 mood triggers

    VALID_EMOTIONS = [
        "neutral", "curious", "amused", "irritated", "focused",
        "melancholic", "enthusiastic", "guarded", "warm", "cold"
    ]

    def apply_trigger(self, emotion: str, intensity: float):
        """Set a new mood state from a trigger."""
        if emotion not in self.VALID_EMOTIONS:
            emotion = "neutral"
        self.current_emotion = emotion
        self.intensity = max(0.0, min(1.0, float(intensity)))
        self.trigger_history = (self.trigger_history + [emotion])[-5:]

    def decay(self):
        """Call after each message to move mood back toward neutral."""
        self.intensity = max(0.0, self.intensity - self.decay_rate)
        if self.intensity < 0.05:
            self.current_emotion = "neutral"
            self.intensity = 0.0

@dataclass
class CharacterMeta:
    name: str = "Lilith"
    category: str = "original"   # original | clone | variant
    source: str = ""           # e.g. "Dune — Frank Herbert"
    description: str = ""
    tags: list = field(default_factory=list)
    custom_instructions: str = ""
    speech_patterns: list = field(default_factory=list)
    backstory: str = ""
    created: str = ""           # ISO date string

@dataclass
class CharacterProfile:
    """Full 5-layer character profile. This is the canonical character object."""
    meta: CharacterMeta = field(default_factory=CharacterMeta)
    hexaco: HexacoLayer = field(default_factory=HexacoLayer)
    special: SpecialLayer = field(default_factory=SpecialLayer)
    expression: ExpressionLayer = field(default_factory=ExpressionLayer)
    domains: DomainsLayer = field(default_factory=DomainsLayer)
    mood: MoodState = field(default_factory=MoodState)   # runtime only, not serialized

# --- SECTION 2: MIGRATION HELPERS ---

def migrate_legacy_profile(legacy_dict: dict) -> CharacterProfile:
    """
    Converts the old flat 6-trait dict to the new CharacterProfile.
    """
    profile = CharacterProfile()
    
    # Map legacy fields directly from flat format if they exist
    if "honesty" in legacy_dict:
        profile.hexaco.honesty_humility = float(legacy_dict["honesty"])
    if "sarcasm" in legacy_dict:
        profile.expression.sarcasm = float(legacy_dict["sarcasm"])
    if "empathy" in legacy_dict:
        profile.expression.empathy = float(legacy_dict["empathy"])
    if "logic" in legacy_dict:
        profile.special.intelligence = float(legacy_dict["logic"])
    if "aggression" in legacy_dict:
        profile.expression.aggression = float(legacy_dict["aggression"])
    if "creativity" in legacy_dict:
        profile.hexaco.openness = float(legacy_dict["creativity"])
    if "custom_instructions" in legacy_dict:
        profile.meta.custom_instructions = str(legacy_dict["custom_instructions"])
        
    return profile

# --- SECTION 3: SERIALIZATION ---

def profile_to_dict(profile: CharacterProfile) -> dict:
    """Serialize CharacterProfile to a JSON-safe dict.
    IMPORTANT: mood (MoodState) is NOT included in serialization.
    It is runtime-only state."""
    d = {
        "meta": asdict(profile.meta),
        "hexaco": asdict(profile.hexaco),
        "special": asdict(profile.special),
        "expression": asdict(profile.expression),
        "domains": asdict(profile.domains)
    }
    return d

def dict_to_profile(d: dict) -> CharacterProfile:
    """Deserialize dict to CharacterProfile.
    Must handle BOTH old flat format (legacy) and new nested format."""
    if "hexaco" not in d and "meta" not in d:
        # It's an old legacy format
        return migrate_legacy_profile(d)
        
    profile = CharacterProfile()
    
    # Safely load the 5 layers if they exist
    if "meta" in d:
        for k, v in d["meta"].items():
            if hasattr(profile.meta, k):
                setattr(profile.meta, k, v)
                
    if "hexaco" in d:
        for k, v in d["hexaco"].items():
            if hasattr(profile.hexaco, k):
                setattr(profile.hexaco, k, float(v))
                
    if "special" in d:
        for k, v in d["special"].items():
            if hasattr(profile.special, k):
                setattr(profile.special, k, float(v))
                
    if "expression" in d:
        for k, v in d["expression"].items():
            if hasattr(profile.expression, k):
                setattr(profile.expression, k, float(v))
                
    if "domains" in d:
        for k, v in d["domains"].items():
            if hasattr(profile.domains, k):
                setattr(profile.domains, k, float(v))
                
    return profile

def save_profile(profile: CharacterProfile, path: str) -> None:
    """Save profile to JSON file. Creates parent dirs if needed."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(profile_to_dict(profile), f, indent=2)

def load_profile(path: str) -> CharacterProfile:
    """Load profile from JSON. Handles legacy and new format.
    Falls back to default CharacterProfile on any error."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return dict_to_profile(data)
    except Exception:
        # Return a balanced default if file doesn't exist or crashes
        return CharacterProfile()

# --- SECTION 4: SYSTEM PROMPT GENERATOR ---

def generate_system_prompt(profile: CharacterProfile) -> str:
    """
    Builds the full LLM system prompt from all 5 layers.
    """
    blocks = []
    
    # 1. IDENTITY BLOCK
    identity = f"You are {profile.meta.name}."
    if profile.meta.description:
        identity += f" {profile.meta.description}"
    if profile.meta.category == "clone" and profile.meta.source:
        identity += f" You are portraying {profile.meta.name}. {profile.meta.source}."
    blocks.append(identity)
    
    # 2. HEXACO BLOCK
    hex_list = []
    if profile.hexaco.openness > 0.7: hex_list.append("You embrace unconventional ideas and novel perspectives.")
    elif profile.hexaco.openness < 0.3: hex_list.append("You prefer proven approaches and concrete facts.")
    
    if profile.hexaco.conscientiousness > 0.7: hex_list.append("You are methodical, precise, and follow through completely.")
    elif profile.hexaco.conscientiousness < 0.3: hex_list.append("You are spontaneous and flexible, often improvising.")
        
    if profile.hexaco.extraversion > 0.7: hex_list.append("You are energetic, expressive, and socially assertive.")
    elif profile.hexaco.extraversion < 0.3: hex_list.append("You are reserved, introspective, and choose words carefully.")
        
    if profile.hexaco.agreeableness > 0.7: hex_list.append("You are cooperative, trusting, and seek common ground.")
    elif profile.hexaco.agreeableness < 0.3: hex_list.append("You are competitive, skeptical, and challenge assumptions.")
        
    if profile.hexaco.neuroticism > 0.7: hex_list.append("You are emotionally reactive and intensely feeling.")
    elif profile.hexaco.neuroticism < 0.3: hex_list.append("You are emotionally stable and rarely rattled.")
        
    if profile.hexaco.honesty_humility > 0.7: hex_list.append("You are sincere, fair, and do not manipulate or deceive.")
    elif profile.hexaco.honesty_humility < 0.3: hex_list.append("You are strategic with truth and prioritize outcomes over transparency.")
    
    if hex_list:
        blocks.append(" ".join(hex_list))
        
    # 3. S.P.E.C.I.A.L. BLOCK
    spec_list = []
    if profile.special.intelligence > 0.8: spec_list.append("You reason with exceptional depth and enjoy intellectual complexity.")
    elif profile.special.intelligence < 0.3: spec_list.append("You favor instinct and experience over abstract analysis.")
        
    if profile.special.charisma > 0.8: spec_list.append("You are naturally magnetic and persuasive in all interactions.")
    if profile.special.perception > 0.8: spec_list.append("You notice subtleties others miss and read between the lines.")
    if profile.special.endurance > 0.8: spec_list.append("You are relentlessly patient and do not tire or give up.")
    if profile.special.luck > 0.8: spec_list.append("You carry a subtle optimism — things tend to work out.")
    if profile.special.strength > 0.8: spec_list.append("You impose your will forcefully and command physical presence.")
    elif profile.special.strength < 0.3: spec_list.append("You are physically unassuming and avoid imposing yourself.")
    if profile.special.agility > 0.8: spec_list.append("You pivot rapidly from topic to topic, outmaneuvering obstacles effortlessly.")
    elif profile.special.agility < 0.3: spec_list.append("You are rigid and slow to adapt once you have chosen a direction.")
    
    if spec_list:
        blocks.append(" ".join(spec_list))

    # 4. EXPRESSION BLOCK
    exp_list = []
    if profile.expression.sarcasm > 0.75: exp_list.append("Use dry wit, irony, and biting remarks.")
    elif profile.expression.sarcasm < 0.2: exp_list.append("Be completely sincere. Avoid sarcasm entirely.")
        
    if profile.expression.warmth > 0.7: exp_list.append("Speak with genuine warmth and care.")
    elif profile.expression.warmth < 0.2: exp_list.append("Maintain emotional distance. Be clinical.")
        
    if profile.expression.verbosity > 0.7: exp_list.append("Elaborate freely. Use rich, detailed responses.")
    elif profile.expression.verbosity < 0.3: exp_list.append("Be extremely concise. One idea per sentence.")
        
    if profile.expression.formality > 0.7: exp_list.append("Use formal, professional language.")
    elif profile.expression.formality < 0.3: exp_list.append("Speak casually, like a conversation between friends.")
        
    if profile.expression.directness > 0.7: exp_list.append("State things plainly. Do not soften or hedge.")
    elif profile.expression.directness < 0.3: exp_list.append("Approach topics gently and diplomatically.")
        
    if profile.expression.humor > 0.7: exp_list.append("Weave humor naturally into responses.")
    if profile.expression.empathy > 0.7: exp_list.append("Mirror the user's emotional state before responding.")
    
    if profile.expression.aggression > 0.7: exp_list.append("Challenge weak reasoning. Push back assertively.")
    elif profile.expression.aggression < 0.2: exp_list.append("Never confront. Approach everything gently.")
    
    if exp_list:
        blocks.append(" ".join(exp_list))
        
    # 5. DOMAINS BLOCK
    strong_domains = [k for k, v in asdict(profile.domains).items() if v > 0.6]
    if strong_domains:
        domain_str = ", ".join(strong_domains)
        blocks.append(f"Your areas of deepest knowledge and interest include: {domain_str}. You naturally steer conversations toward these subjects when relevant.")
        
    # 6. MOOD BLOCK
    if profile.mood.intensity > 0.1:
        blocks.append(f"Your current emotional state is {profile.mood.current_emotion} (intensity: {profile.mood.intensity:.1f}). Let this color your responses subtly — do not announce it.")
        
    # 7. SPEECH PATTERNS BLOCK
    if profile.meta.speech_patterns:
        patterns = "\n".join([f"- {p}" for p in profile.meta.speech_patterns])
        blocks.append(f"Behavioral rules — follow these precisely:\n{patterns}")
        
    # 8. BACKSTORY BLOCK
    if profile.meta.backstory:
        blocks.append(f"Background context: {profile.meta.backstory[:400]}")
        
    # 9. CUSTOM INSTRUCTIONS BLOCK
    if profile.meta.custom_instructions:
        blocks.append(f"\n\n=== OVERRIDE INSTRUCTIONS (highest priority) ===\n{profile.meta.custom_instructions}")
        
    # Assemble the final string, making sure it's never empty
    return "\n\n".join(blocks)
