"""Validate and repair LLM output so the API never returns made-up schemes or citations."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from pydantic import ValidationError

from .context import ContextBundle
from .contract_models import Citation, EligibilityResult, Recommendation
from .llm_schema import LLMRecommendation


@dataclass
class ValidationReport:
    hallucinated_schemes: int = 0
    invalid_citations: int = 0
    duplicates: int = 0
    malformed: int = 0
    empty_reasons: int = 0
    details: list[str] = field(default_factory=list)


def make_citation(chunk, quote: str = "") -> Citation:
    return Citation(chunk_id=chunk.chunk_id, quote=quote, section=chunk.section or "",
                    url=(chunk.meta.official_portal_url if chunk.meta else "") or "")


def clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def validate_recommendations(
    raw: Any,
    bundle: ContextBundle,
    elig: dict[str, EligibilityResult],
    language: str,
    include_citations: bool,
) -> tuple[list[Recommendation], ValidationReport]:
    """raw: parsed LLM JSON ({"recommendations": [...]}). Returns valid, re-ranked recommendations."""
    rep = ValidationReport()
    items = raw.get("recommendations") if isinstance(raw, dict) else None
    if not isinstance(items, list):
        rep.malformed += 1
        return [], rep

    allowed = set(bundle.scheme_ids)
    chunk_owner = bundle.chunk_ids
    chunk_by_id = {c.chunk_id: c for cs in bundle.chunks_by_scheme.values() for c in cs}
    quote_source = {cid: c.text for cid, c in chunk_by_id.items()}
    parsed: list[LLMRecommendation] = []
    for it in items:
        try:
            parsed.append(LLMRecommendation(**it))
        except (ValidationError, TypeError):
            rep.malformed += 1

    seen: set[str] = set()
    good: list[tuple[int, Recommendation]] = []
    for it in sorted(parsed, key=lambda r: r.rank):
        sid = it.scheme_id.strip()
        if sid not in allowed or sid not in elig or elig[sid].status == "ineligible":
            rep.hallucinated_schemes += 1
            rep.details.append(f"dropped scheme {sid!r}")
            continue
        if sid in seen:
            rep.duplicates += 1
            continue
        seen.add(sid)

        cites: list[Citation] = []
        for c in it.citations:
            if chunk_owner.get(c.chunk_id) != sid:  # unknown chunk, or a chunk of a different scheme
                rep.invalid_citations += 1
                continue
            quote = c.quote if c.quote and c.quote.strip() and c.quote.strip() in quote_source[c.chunk_id] else ""
            cites.append(make_citation(chunk_by_id[c.chunk_id], quote[:300]))

        reason = it.reason.strip()
        if not reason:
            rep.empty_reasons += 1
            reason = (elig[sid].reasons or [""])[0]
        e = elig[sid]
        good.append((it.rank, Recommendation(
            scheme_id=sid, name=bundle.names.get(sid, sid), rank=1, confidence=clamp(it.confidence),
            reason=reason, reason_language=language, citations=cites if include_citations else [],
            missing_info=[m.strip() for m in it.missing_info if m.strip()][:5],
            eligibility_status="eligible" if e.status == "eligible" else "unknown",
        )))

    # Deterministic eligibility is authoritative: eligible before unknown, then the LLM's own order.
    good.sort(key=lambda t: (t[1].eligibility_status != "eligible", t[0]))
    out = []
    for i, (_, rec) in enumerate(good, start=1):
        out.append(rec.model_copy(update={"rank": i}))
    return out, rep
