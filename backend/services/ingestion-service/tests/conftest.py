import hashlib
import json
import math
from pathlib import Path

import httpx
import pytest
from qdrant_client import AsyncQdrantClient

from ingestion_service.config import Settings
from ingestion_service.main import build_ingestor

DIM = 16


def fake_vec(text: str) -> list[float]:
    v = [0.0] * DIM
    for w in text.lower().split():
        h = int.from_bytes(hashlib.sha256(w.encode()).digest()[:4], "big")
        v[h % DIM] += 1.0
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


class FakeEmbedder:
    """MockTransport handler standing in for embedding-service."""

    def __init__(self):
        self.calls = 0
        self.texts: list[str] = []
        self.fail = False

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == "/ready":
            return httpx.Response(200, json={"ready": True})
        self.calls += 1
        if self.fail:
            return httpx.Response(503, json={"detail": "down"})
        body = json.loads(request.content)
        self.texts.extend(body["texts"])
        return httpx.Response(200, json={
            "vectors": [fake_vec(t) for t in body["texts"]], "dim": DIM, "model_id": f"fake-{DIM}", "truncated": [False] * len(body["texts"]),
        })


def make_pdf(text: str) -> bytes:
    stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET"
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, o in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return out


@pytest.fixture
def docs(tmp_path) -> Path:
    d = tmp_path / "docs"
    d.mkdir()
    return d


@pytest.fixture
def embedder():
    return FakeEmbedder()


@pytest.fixture
def make(docs, embedder):
    created = []

    def _make(**kw):
        s = Settings(docs_dir=str(docs), state_dir=":memory:", qdrant_url=":memory:", embedding_url="http://emb:8002", **kw)
        ing = build_ingestor(s, qdrant=AsyncQdrantClient(":memory:"), transport=httpx.MockTransport(embedder))
        created.append(ing)
        return ing

    return _make


SCHEME_MD = """---
scheme_id: "pm_test"
name: "PM Test"
state_scope: "All"
is_central: true
category: "Agriculture"
min_age: 18
max_age: null
---
# PM Test

## Summary
Income support for farmers.

## Benefit
Six thousand rupees per year.
"""
