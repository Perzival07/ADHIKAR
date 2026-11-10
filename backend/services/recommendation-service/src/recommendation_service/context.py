"""Build the (budgeted) LLM context from retrieved chunks."""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from .contract_models import Chunk, EligibilityResult


def est_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def _attr(s: str) -> str:
    return s.replace('"', "'")


_TAG = re.compile(r"<(/?)doc", re.IGNORECASE)


def escape_doc_text(text: str) -> str:
    """Chunk text must never be able to close or forge a <doc> wrapper (prompt-injection defence)."""
    return _TAG.sub(r"&lt;\1doc", text)


@dataclass
class ContextBundle:
    candidates_text: str
    docs_text: str
    chunks_by_scheme: dict[str, list[Chunk]] = field(default_factory=dict)
    names: dict[str, str] = field(default_factory=dict)

    @property
    def scheme_ids(self) -> list[str]:
        return list(self.chunks_by_scheme)

    @property
    def chunk_ids(self) -> dict[str, str]:
        """chunk_id -> scheme_id for every chunk shown to the model."""
        return {c.chunk_id: sid for sid, cs in self.chunks_by_scheme.items() for c in cs}


def group_by_scheme(chunks: list[Chunk]) -> dict[str, list[Chunk]]:
    out: dict[str, list[Chunk]] = {}
    for c in chunks:
        out.setdefault(c.scheme_id, []).append(c)
    return out


def by_eligibility(scheme_ids: list[str], elig: dict[str, EligibilityResult]) -> list[str]:
    """Eligible before unknown, then higher eligibility score; the incoming (retrieval) order breaks ties.

    Same precedence as the rules-only fallback. Without it a scheme matched by its own specific rule (score 1.0)
    can be pushed out of the top results by schemes that only passed the generic rules, purely on retrieval order.
    """
    def key(sid: str) -> tuple[bool, float]:
        e = elig.get(sid)
        return (e is None or e.status != "eligible", -(e.score if e else 0.0))
    return sorted(scheme_ids, key=key)  # stable sort keeps retrieval order within equal keys


def build_context(chunks: list[Chunk], elig: dict[str, EligibilityResult], budget_tokens: int) -> ContextBundle:
    by_scheme = group_by_scheme(chunks)
    grouped = {sid: by_scheme[sid] for sid in by_eligibility(list(by_scheme), elig)}
    used = 0
    chosen: dict[str, list[Chunk]] = {}
    for sid, cs in grouped.items():
        header = est_tokens(f"- {sid} | status | {elig[sid].reasons[0] if sid in elig and elig[sid].reasons else ''}"[:260]) + 8
        picked: list[Chunk] = []
        cost = header
        for c in cs:
            ct = est_tokens(c.text) + 12
            if used + cost + ct > budget_tokens:
                if not chosen and not picked:  # always keep at least one (truncated) chunk
                    c = c.model_copy(update={"text": c.text[: max(200, (budget_tokens - used - cost - 12) * 4)]})
                    ct = est_tokens(c.text) + 12
                else:
                    break
            picked.append(c)
            cost += ct
        if not picked:
            break  # budget exhausted
        chosen[sid] = picked
        used += cost
        if used >= budget_tokens:
            break

    names = {sid: (cs[0].meta.name if cs[0].meta and cs[0].meta.name else sid) for sid, cs in chosen.items()}
    cand_lines, doc_blocks = [], []
    for sid, cs in chosen.items():
        e = elig.get(sid)
        status = e.status if e else "eligible"
        why = (e.reasons[0] if e and e.reasons else "")[:220]
        missing = f" | missing: {', '.join(e.missing_fields)}" if e and e.missing_fields else ""
        cand_lines.append(f"- {sid} | {names[sid]} | {status}{missing} | {why}")
        for c in cs:
            warn = ' flagged="true"' if c.flagged else ""
            doc_blocks.append(f'<doc id="{_attr(c.chunk_id)}" scheme="{_attr(sid)}"{warn}>\n{escape_doc_text(c.text)}\n</doc>')
    return ContextBundle("\n".join(cand_lines), "\n".join(doc_blocks), chosen, names)
