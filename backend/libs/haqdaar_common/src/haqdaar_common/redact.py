from __future__ import annotations

import hashlib
import json
from typing import Any

# Sensitive fields are never logged raw (caste category, income, disability, marital status ...).
_COARSE_KEEP = {"state"}


def profile_hash(profile: dict[str, Any]) -> str:
    """Stable short hash of a profile, safe to log and use as a cache key."""
    canonical = json.dumps(profile, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def redact_profile(profile: dict[str, Any]) -> dict[str, Any]:
    """Loggable view of a profile: hash + coarse state only."""
    out: dict[str, Any] = {"profile_hash": profile_hash(profile)}
    for k in _COARSE_KEEP:
        if k in profile:
            out[k] = profile[k]
    return out
