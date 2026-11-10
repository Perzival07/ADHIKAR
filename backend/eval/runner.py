from __future__ import annotations

import time
from collections.abc import Callable
from pathlib import Path

import httpx

from .golden import Case, load_golden
from .metrics import CaseResult, aggregate, parse_prometheus, recall_at_k

COUNTERS = ["llm_items_total", "hallucinated_schemes_dropped_total", "llm_citations_total", "invalid_citations_dropped_total"]


def corpus_ids(docs_dir: Path | None) -> set[str] | None:
    """Scheme ids known to the documents folder (for the unknown-id check). None if unavailable."""
    if not docs_dir or not docs_dir.exists():
        return None
    ids = set()
    for p in docs_dir.glob("*.md"):
        stem = p.stem
        if stem.lower() == "readme":
            continue
        head, _, tail = stem.rpartition(".")
        ids.add(head if head and len(tail) in (2, 3) and tail.isalpha() else stem)
    for d in docs_dir.iterdir():
        if d.is_dir():
            ids.add(d.name)
    return ids


def scrape_counters(client: httpx.Client, target: str, token: str = "") -> dict[str, float] | None:
    """Read server-side counters from /metrics (Prometheus text). None when unavailable."""
    try:
        r = client.get(f"{target}/metrics", timeout=5.0, headers={"Authorization": f"Bearer {token}"} if token else None)
    except httpx.HTTPError:
        return None
    if r.status_code != 200:
        return None
    parsed = parse_prometheus(r.text)
    found = {}
    for name in COUNTERS:
        for key in (name, f"haqdaar_{name}", f"reco_{name}"):
            if key in parsed:
                found[name] = parsed[key]
                break
    return found or None


def evaluate_case(client: httpx.Client, target: str, case: Case, known_ids: set[str] | None) -> CaseResult:
    res = CaseResult(id=case.id, language=case.language)
    body = {"profile": case.profile, "language": case.language, "top_n": case.top_n, "include_citations": True}
    t0 = time.perf_counter()
    try:
        r = client.post(f"{target}/v1/recommendations", json=body, headers={"Cache-Control": "no-cache"})
    except httpx.HTTPError as e:
        res.error = f"{e.__class__.__name__}: {e}"
        res.latency_ms = (time.perf_counter() - t0) * 1000
        return res
    res.latency_ms = (time.perf_counter() - t0) * 1000
    res.status = r.status_code
    if r.status_code != 200:
        res.error = r.text[:200]
        return res

    d = r.json()
    recs, more = d.get("recommendations", []), d.get("more", [])
    res.mode, res.fallback_reason = d.get("mode", ""), d.get("fallback_reason")
    res.returned_ids = [x["scheme_id"] for x in recs] + [x["scheme_id"] for x in more]
    res.rec_count = len(recs)
    res.rec_with_citation = sum(1 for x in recs if x.get("citations"))
    res.reason_languages = sorted({x.get("reason_language", "") for x in recs})
    res.recall5 = recall_at_k(res.returned_ids, case.must_include, 5)
    res.recall10 = recall_at_k(res.returned_ids, case.must_include, 10)
    res.forbidden_count = len(case.must_not_include)
    res.violations = sorted(set(case.must_not_include) & set(res.returned_ids))
    if known_ids is not None:
        res.unknown_ids = sorted({i for i in res.returned_ids if i not in known_ids})
    want_lang = case.expect.get("reason_language")
    if want_lang and res.mode == "rag" and res.reason_languages != [want_lang]:
        res.expect_failures.append(f"reason_language {res.reason_languages} != [{want_lang!r}]")
    if "mode" in case.expect and res.mode != case.expect["mode"]:
        res.expect_failures.append(f"mode {res.mode!r} != {case.expect['mode']!r}")
    if case.top_n and len(recs) > case.top_n:
        res.expect_failures.append(f"returned {len(recs)} recommendations for top_n={case.top_n}")
    return res


def run(target: str, tag: str, golden_dir: Path | None = None, docs_dir: Path | None = None, limit: int | None = None,
        timeout: float = 180.0, progress: Callable[[CaseResult], None] | None = None, transport=None, metrics_token: str = "") -> dict:
    target = target.rstrip("/")
    cases = load_golden(golden_dir) if golden_dir else load_golden()
    if limit:
        cases = cases[:limit]
    known = corpus_ids(docs_dir)
    results: list[CaseResult] = []
    with httpx.Client(timeout=timeout, transport=transport) as client:
        before = scrape_counters(client, target, metrics_token)
        for case in cases:  # sequential on purpose: honest latency, no self-inflicted queueing on a local GPU
            r = evaluate_case(client, target, case, known)
            results.append(r)
            if progress:
                progress(r)
        after = scrape_counters(client, target, metrics_token)
    deltas = {k: after[k] - before.get(k, 0.0) for k in after} if before is not None and after else None
    return {
        "tag": tag, "target": target, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cases": len(cases), "server_counters_available": deltas is not None,
        "metrics": aggregate(results, deltas), "per_case": [r.to_dict() for r in results],
    }
