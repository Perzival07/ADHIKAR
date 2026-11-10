import json

import httpx
from fastapi.testclient import TestClient

from retrieval_service.config import Settings
from retrieval_service.main import create_app

from .conftest import FakeEmbedder, seed


async def test_embedding_breaker_fails_fast_then_recovers(qdrant, corpus):
    await seed(qdrant, corpus)
    emb = FakeEmbedder()
    emb.fail = True
    app = create_app(Settings(qdrant_url=":memory:", embedding_url="http://emb:8002", breaker_threshold=3), qdrant=qdrant,
                     transport=httpx.MockTransport(emb))
    with TestClient(app) as c:
        for _ in range(3):
            assert "returned 503" in c.post("/v1/search", json={"query": "x"}).json()["detail"]
        calls = len(emb.requests)
        r = c.post("/v1/search", json={"query": "x"})
        assert r.status_code == 503 and "circuit open" in r.json()["detail"] and len(emb.requests) == calls  # not called

        emb.fail = False
        app.state.searcher.embed_breaker.opened_at -= 100
        assert c.post("/v1/search", json={"query": "income support"}).status_code == 200
        assert app.state.searcher.embed_breaker.state == "closed"


def test_search_metrics(make_app, qdrant, corpus, embedder):
    import asyncio

    asyncio.run(seed(qdrant, corpus))
    with TestClient(make_app()) as c:
        c.post("/v1/search", json={"query": "income support"})
        c.post("/v1/search", json={"query": "x", "filters": {"scheme_ids": []}})
        text = c.get("/metrics").text
    assert 'retrieval_searches_total{outcome="ok"} 1' in text and 'retrieval_searches_total{outcome="empty"} 1' in text
    assert "retrieval_chunks_returned_total" in text and json
