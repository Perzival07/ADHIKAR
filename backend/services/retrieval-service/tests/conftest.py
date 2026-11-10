import hashlib
import json
import math

import httpx
import pytest
from qdrant_client import AsyncQdrantClient, models

from retrieval_service.config import Settings
from retrieval_service.main import create_app

DIM = 32
MODEL_ID = f"fake-{DIM}"
COLLECTION = f"scheme_chunks__{MODEL_ID}"


def fake_vec(text: str) -> list[float]:
    v = [0.0] * DIM
    for w in text.lower().split():
        v[int.from_bytes(hashlib.sha256(w.strip(".,").encode()).digest()[:4], "big") % DIM] += 1.0
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


class FakeEmbedder:
    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.fail = False

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == "/ready":
            return httpx.Response(200, json={"ready": True})
        self.requests.append(request)
        if self.fail:
            return httpx.Response(503, json={"detail": "down"})
        texts = json.loads(request.content)["texts"]
        return httpx.Response(200, json={"vectors": [fake_vec(t) for t in texts], "dim": DIM, "model_id": MODEL_ID, "truncated": [False] * len(texts)})


def chunk(cid, scheme, text, *, state="All", central=True, lang="en", status="verified", section="S", flagged=False):
    return {
        "chunk_id": cid, "scheme_id": scheme, "name": scheme.title(), "text": text, "section": section, "page": None,
        "source": f"{scheme}.md", "flagged": flagged, "state_scope": state, "is_central": central, "category": "x",
        "gender_eligibility": "All", "income_ceiling": "No Limit", "min_age": None, "max_age": None, "education_level": "All",
        "official_portal_url": "", "last_verified_date": "", "language": lang, "source_type": "corpus", "status": status,
    }


async def seed(client: AsyncQdrantClient, chunks: list[dict], name: str = COLLECTION):
    await client.create_collection(name, vectors_config=models.VectorParams(size=DIM, distance=models.Distance.COSINE))
    import uuid

    await client.upsert(name, [
        models.PointStruct(id=str(uuid.uuid5(uuid.NAMESPACE_URL, c["chunk_id"])), vector=fake_vec(c["text"]), payload=c) for c in chunks
    ])


@pytest.fixture
def embedder():
    return FakeEmbedder()


@pytest.fixture
def qdrant():
    return AsyncQdrantClient(":memory:")


@pytest.fixture
def make_app(qdrant, embedder):
    def _make(**kw):
        s = Settings(qdrant_url=":memory:", embedding_url="http://emb:8002", **kw)
        return create_app(s, qdrant=qdrant, transport=httpx.MockTransport(embedder))

    return _make


@pytest.fixture
def corpus():
    return [
        chunk("k1", "pm_kisan", "Income support of rupees 6000 per year for landholding farmer families"),
        chunk("k2", "pm_kisan", "Documents required: Aadhaar card and land ownership record Khatauni"),
        chunk("k3", "pm_kisan", "How to apply for PM-KISAN at the common service centre"),
        chunk("a1", "ayushman", "Health cover of rupees 5 lakh per family per year for hospital treatment"),
        chunk("s1", "odisha_subhadra", "Subhadra Yojana gives Odisha women 10000 rupees per year", state="Odisha", central=False),
        chunk("s2", "kerala_only", "Kerala only scheme gives farmers income support in Kerala", state="Kerala", central=False),
        chunk("s3", "kerala_health", "Kerala health insurance for families hospital treatment", state="Kerala", central=False),
        chunk("h1", "pm_kisan", "किसान परिवारों को प्रति वर्ष 6000 रुपये की आय सहायता", lang="hi"),
        chunk("u1", "unverified_x", "farmer income support rupees unverified scheme", status="unverified"),
        chunk("w1", "wb_scheme", "West Bengal scheme farmers income support", state="West Bengal", central=False),
    ]
