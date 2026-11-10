"""Flag chunks containing instruction-like text. Text is kept faithful; the flag lets the
recommender wrap such chunks with an extra warning."""
import re

_PATTERNS = [
    r"ignore (all |any |the )?(previous|prior|above|earlier) (instructions|prompts?|rules)",
    r"disregard (all |any |the )?(previous|prior|above|earlier)",
    r"(^|\n)\s*(system|assistant)\s*:",
    r"you are now\b",
    r"new instructions?\s*:",
    r"(do not|don't) (follow|obey) (the )?(previous|above|system)",
    r"(always|only) recommend\b",
    r"reveal (your|the) (system )?prompt",
    r"</?(doc|system|instructions?)\b",
]
_RE = re.compile("|".join(f"(?:{p})" for p in _PATTERNS), re.IGNORECASE)


def looks_like_instructions(text: str) -> bool:
    return bool(_RE.search(text))
