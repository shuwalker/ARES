"""Control tags — parse [face:x] and [anim:y] directives from LLM output.

Any brain backend can emit control tags in its response text. These get
stripped before display and converted to face state changes via state_mapper.

Tag format: [face:happy], [anim:wave], [face:thinking], etc.
Multiple tags per response are supported.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class ParsedTags:
    """Result of parsing control tags from a response string."""

    clean_text: str
    face_tags: list[str] = field(default_factory=list)
    anim_tags: list[str] = field(default_factory=list)


# Regex: matches [face:word] or [anim:word] patterns
TAG_PATTERN = re.compile(r"\[(face|anim):(\w+)\]")


def parse_control_tags(text: str) -> ParsedTags:
    """Extract and strip control tags from LLM output text.

    Returns the cleaned text (tags removed) and lists of face/anim directives.

    Example:
        >>> result = parse_control_tags("Hello! [face:happy] How are you?")
        >>> result.clean_text
        'Hello!  How are you?'
        >>> result.face_tags
        ['happy']
    """
    face_tags: list[str] = []
    anim_tags: list[str] = []

    def _replace(match: re.Match) -> str:
        kind = match.group(1)
        value = match.group(2)
        if kind == "face":
            face_tags.append(value)
        elif kind == "anim":
            anim_tags.append(value)
        return ""

    clean_text = TAG_PATTERN.sub(_replace, text)
    # Collapse multiple spaces left by tag removal
    clean_text = re.sub(r"  +", " ", clean_text).strip()

    return ParsedTags(clean_text=clean_text, face_tags=face_tags, anim_tags=anim_tags)


def tags_to_face_events(tags: ParsedTags) -> list[tuple[str, str]]:
    """Convert parsed tags to (face_state, expression) pairs.

    Uses state_mapper.CONTROL_TAG_MAP for lookups.
    Unrecognized tags are silently skipped.
    """
    from ares.core.state_mapper import CONTROL_TAG_MAP

    events: list[tuple[str, str]] = []
    for tag in tags.face_tags:
        key = f"face:{tag}"
        if key in CONTROL_TAG_MAP:
            events.append(CONTROL_TAG_MAP[key])
    for tag in tags.anim_tags:
        key = f"anim:{tag}"
        if key in CONTROL_TAG_MAP:
            events.append(CONTROL_TAG_MAP[key])
    return events
