from __future__ import annotations

import hashlib
import itertools
import math
import re

from .base import EmbeddingProvider

# \w misses Indic vowel signs / combining marks (they are not "alphanumeric"), which would split words like
# "किसान" into fragments. Include the Indic blocks and Arabic-script marks (Urdu) explicitly.
_TOKEN = re.compile(r"[\w\u0900-\u0DFF\u1C50-\u1C7F\uABC0-\uABFF\u064B-\u065F\u0670]+", re.UNICODE)


class HashProvider(EmbeddingProvider):
    """Deterministic offline fake: hashed bag-of-words (+bigrams), L2-normalised.

    Texts sharing words get high cosine similarity, so retrieval tests stay meaningful.
    """

    name = "hash"

    def __init__(self, dim: int = 384):
        self.dim = dim

    def _vec(self, text: str) -> list[float]:
        toks = [t.lower() for t in _TOKEN.findall(text)]
        feats = toks + [f"{a}_{b}" for a, b in itertools.pairwise(toks)]
        v = [0.0] * self.dim
        for f in feats:
            h = int.from_bytes(hashlib.sha256(f.encode("utf-8")).digest()[:8], "big")
            sign = 1.0 if (h >> 63) & 1 else -1.0
            v[h % self.dim] += sign * (1.0 if "_" not in f else 0.5)
        n = math.sqrt(sum(x * x for x in v))
        return [x / n for x in v] if n else v

    async def embed(self, texts: list[str], kind: str) -> list[list[float]]:
        return [self._vec(t) for t in texts]

    async def info(self) -> tuple[str, int]:
        return f"hash-{self.dim}", self.dim

    async def ready(self) -> tuple[bool, str]:
        return True, "ok"
