from __future__ import annotations

import json
from pathlib import Path

from .metrics import DIRECTION

ORDER = ["cases", "recall@5", "recall@10", "violation_rate", "unknown_id_rate", "model_hallucination_rate",
         "citation_coverage", "model_citation_drop_rate", "json_valid_rate", "fallback_rate", "error_rate",
         "expectation_pass_rate", "latency_p50_ms", "latency_p95_ms"]


def fmt(name: str, v: float | None) -> str:
    if v is None:
        return "n/a"
    if name.endswith("_ms"):
        return f"{v:,.0f} ms"
    if name == "cases":
        return str(int(v))
    return f"{v:.3f}"


def summary(result: dict) -> str:
    m = result["metrics"]
    rows = [f"| {k} | {fmt(k, m.get(k))} |" for k in ORDER if k in m]
    notes = "" if result.get("server_counters_available") else "\n_model_* metrics need the server's /metrics endpoint (n/a here)._"
    return f"### {result['tag']}  ({result['target']}, {result['timestamp']})\n\n| metric | value |\n|---|---|\n" + "\n".join(rows) + notes


def failures(result: dict, limit: int = 15) -> list[str]:
    out = []
    for c in result["per_case"]:
        problems = []
        if c["status"] != 200:
            problems.append(f"HTTP {c['status']} {c.get('error') or ''}".strip())
        if c["recall10"] is not None and c["recall10"] < 1:
            problems.append(f"recall@10={c['recall10']:.2f}")
        if c["violations"]:
            problems.append(f"forbidden: {c['violations']}")
        if c["unknown_ids"]:
            problems.append(f"unknown ids: {c['unknown_ids']}")
        problems += c["expect_failures"]
        if problems:
            out.append(f"- {c['id']}: " + "; ".join(problems))
    return out[:limit]


def compare(a: dict, b: dict) -> str:
    """Markdown table comparing two runs (A = baseline, B = candidate)."""
    lines = [f"### {a['tag']} vs {b['tag']}", "", f"| metric | {a['tag']} | {b['tag']} | change |", "|---|---|---|---|"]
    for k in ORDER:
        if k not in a["metrics"] and k not in b["metrics"]:
            continue
        va, vb = a["metrics"].get(k), b["metrics"].get(k)
        change = ""
        if va is not None and vb is not None and k != "cases" and va != vb:
            better = (vb > va) == DIRECTION.get(k, True)
            change = ("better" if better else "worse") + f" ({vb - va:+.3f})" if not k.endswith("_ms") else \
                     ("better" if better else "worse") + f" ({vb - va:+,.0f} ms)"
        lines.append(f"| {k} | {fmt(k, va)} | {fmt(k, vb)} | {change} |")
    return "\n".join(lines)


def load(path: str | Path) -> dict:
    return json.loads(Path(path).read_text())
