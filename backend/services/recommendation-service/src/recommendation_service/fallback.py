"""Rules-only ranking: eligibility score + retrieval order, templated reasons. Used when the LLM can't be."""
from __future__ import annotations

from .contract_models import Chunk, EligibilityResult, Recommendation
from .validate import make_citation


def rules_only(
    elig: dict[str, EligibilityResult],
    chunks: list[Chunk],
    include_citations: bool,
    skip: set[str] | None = None,
    start_rank: int = 1,
    ids: list[str] | None = None,
) -> list[Recommendation]:
    skip = skip or set()
    order = {}
    names: dict[str, str] = {}
    best_chunk: dict[str, Chunk] = {}
    for i, c in enumerate(chunks):
        order.setdefault(c.scheme_id, i)
        best_chunk.setdefault(c.scheme_id, c)
        if c.meta and c.meta.name:
            names.setdefault(c.scheme_id, c.meta.name)

    cands = [e for e in elig.values() if e.status in ("eligible", "unknown") and e.scheme_id not in skip]
    if ids is not None:  # caller dictates the order (e.g. retrieval order)
        cands = [elig[i] for i in ids if i in elig and elig[i].status in ("eligible", "unknown") and i not in skip]
    else:
        cands.sort(key=lambda e: (e.status != "eligible", -e.score, order.get(e.scheme_id, 10**9), e.scheme_id))
    out = []
    for i, e in enumerate(cands, start=start_rank):
        cites = []
        if include_citations and e.scheme_id in best_chunk:
            cites = [make_citation(best_chunk[e.scheme_id])]
        out.append(Recommendation(
            scheme_id=e.scheme_id, name=names.get(e.scheme_id, e.scheme_id), rank=i, confidence=min(max(e.score, 0.0), 1.0),
            reason=(e.reasons[0] if e.reasons else "Matches the eligibility rules."), reason_language="en",
            citations=cites, missing_info=list(e.missing_fields),
            eligibility_status="eligible" if e.status == "eligible" else "unknown",
        ))
    return out
