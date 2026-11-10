from __future__ import annotations

import math
import re
from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class CaseResult:
    id: str
    language: str
    status: int = 0
    mode: str = ""
    fallback_reason: str | None = None
    latency_ms: float = 0.0
    returned_ids: list[str] = field(default_factory=list)  # recommendations first, then "more"
    rec_count: int = 0
    rec_with_citation: int = 0
    reason_languages: list[str] = field(default_factory=list)
    recall5: float | None = None
    recall10: float | None = None
    forbidden_count: int = 0  # size of the case's must_not_include list
    violations: list[str] = field(default_factory=list)
    unknown_ids: list[str] = field(default_factory=list)
    expect_failures: list[str] = field(default_factory=list)
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def recall_at_k(returned: list[str], must: list[str], k: int) -> float | None:
    if not must:
        return None
    top = set(returned[:k])
    return sum(1 for m in must if m in top) / len(must)


def percentile(values: list[float], p: float) -> float | None:
    """Nearest-rank percentile."""
    if not values:
        return None
    s = sorted(values)
    return s[max(0, math.ceil(p / 100 * len(s)) - 1)]


def mean(xs: list[float]) -> float | None:
    return sum(xs) / len(xs) if xs else None


JSON_INVALID_REASONS = {"llm_output_invalid", "llm_422"}

# metric name -> True if higher is better
DIRECTION = {
    "recall@5": True, "recall@10": True, "violation_rate": False, "unknown_id_rate": False,
    "citation_coverage": True, "fallback_rate": False, "json_valid_rate": True, "error_rate": False,
    "expectation_pass_rate": True, "latency_p50_ms": False, "latency_p95_ms": False,
    "model_hallucination_rate": False, "model_citation_drop_rate": False,
}


def aggregate(cases: list[CaseResult], server_deltas: dict[str, float] | None = None) -> dict[str, float | None]:
    ok = [c for c in cases if c.status == 200]
    n = len(cases)
    with_must = [c for c in ok if c.recall10 is not None]
    with_forbidden = [c for c in ok if c.forbidden_count > 0]
    recs = sum(c.rec_count for c in ok if c.mode == "rag")
    cited = sum(c.rec_with_citation for c in ok if c.mode == "rag")
    expectations = [c for c in ok]
    out: dict[str, float | None] = {
        "cases": float(n),
        "recall@5": mean([c.recall5 for c in with_must if c.recall5 is not None]),
        "recall@10": mean([c.recall10 for c in with_must if c.recall10 is not None]),
        "violation_rate": (sum(1 for c in with_forbidden if c.violations) / len(with_forbidden)) if with_forbidden else None,
        "unknown_id_rate": (sum(1 for c in ok if c.unknown_ids) / len(ok)) if ok else None,
        "citation_coverage": (cited / recs) if recs else None,
        "fallback_rate": (sum(1 for c in ok if c.mode == "rules_only") / len(ok)) if ok else None,
        "json_valid_rate": (1 - sum(1 for c in ok if c.fallback_reason in JSON_INVALID_REASONS) / len(ok)) if ok else None,
        "error_rate": ((n - len(ok)) / n) if n else None,
        "expectation_pass_rate": (sum(1 for c in expectations if not c.expect_failures) / len(expectations)) if expectations else None,
        "latency_p50_ms": percentile([c.latency_ms for c in ok], 50),
        "latency_p95_ms": percentile([c.latency_ms for c in ok], 95),
        "model_hallucination_rate": None,
        "model_citation_drop_rate": None,
    }
    d = server_deltas or {}
    if d.get("llm_items_total"):
        out["model_hallucination_rate"] = d.get("hallucinated_schemes_dropped_total", 0.0) / d["llm_items_total"]
    if d.get("llm_citations_total"):
        out["model_citation_drop_rate"] = d.get("invalid_citations_dropped_total", 0.0) / d["llm_citations_total"]
    return out


_PROM = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([-+0-9.eE]+|NaN|Inf)$")


def parse_prometheus(text: str) -> dict[str, float]:
    """Sum samples per metric name (labels ignored). Returns {} for non-Prometheus text."""
    out: dict[str, float] = {}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        m = _PROM.match(line.strip())
        if m:
            try:
                out[m.group(1)] = out.get(m.group(1), 0.0) + float(m.group(3))
            except ValueError:
                pass
    return out
