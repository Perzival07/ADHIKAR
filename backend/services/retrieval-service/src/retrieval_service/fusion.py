"""BM25 keyword scoring and Reciprocal Rank Fusion (pure functions)."""
from __future__ import annotations

import math
import re
from collections import Counter

# \w misses Indic vowel signs / combining marks (they are not "alphanumeric"), which would split words like
# "किसान" into fragments. Include the Indic blocks and Arabic-script marks (Urdu) explicitly.
_TOKEN = re.compile(r"[\w\u0900-\u0DFF\u1C50-\u1C7F\uABC0-\uABFF\u064B-\u065F\u0670]+", re.UNICODE)


def tokenize(text: str) -> list[str]:
    return [t.lower() for t in _TOKEN.findall(text)]


def bm25_rank(query: str, docs: dict[str, str], k1: float = 1.5, b: float = 0.75) -> list[tuple[str, float]]:
    """Rank docs (id -> text) against the query. Returns [(id, score)] for docs with score > 0, best first."""
    q = list(dict.fromkeys(tokenize(query)))
    if not q or not docs:
        return []
    toks = {i: tokenize(t) for i, t in docs.items()}
    n = len(toks)
    avg = (sum(len(t) for t in toks.values()) / n) or 1.0
    df = Counter()
    for t in toks.values():
        df.update(set(t) & set(q))
    scored = []
    for i, t in toks.items():
        tf = Counter(t)
        s = 0.0
        for term in q:
            if tf[term] == 0:
                continue
            idf = math.log(1 + (n - df[term] + 0.5) / (df[term] + 0.5))
            s += idf * tf[term] * (k1 + 1) / (tf[term] + k1 * (1 - b + b * len(t) / avg))
        if s > 0:
            scored.append((i, s))
    scored.sort(key=lambda x: (-x[1], x[0]))
    return scored


def rrf(rankings: list[tuple[float, list[str]]], k: int = 60) -> dict[str, float]:
    """Weighted Reciprocal Rank Fusion. rankings = [(weight, [ids best-first]), ...]."""
    fused: dict[str, float] = {}
    for weight, ids in rankings:
        for rank, cid in enumerate(ids, start=1):
            fused[cid] = fused.get(cid, 0.0) + weight / (k + rank)
    return fused
