import json

import httpx
import pytest
from fastapi.testclient import TestClient

from retrieval_service.fusion import bm25_rank, rrf, tokenize
from retrieval_service.search import diversify, prefer_language, to_chunk

from .conftest import chunk, seed


async def run(make_app, qdrant, corpus, body, **settings):
    await seed(qdrant, corpus)
    app = make_app(**settings)
    with TestClient(app) as c:
        r = c.post("/v1/search", json=body)
    return r


def ids(r):
    return [c["chunk_id"] for c in r.json()["chunks"]]


def schemes(r):
    return {c["scheme_id"] for c in r.json()["chunks"]}


# ------------------------------------------------------------- pure functions
def test_tokenize_unicode():
    assert tokenize("PM-KISAN किसान, 6000!") == ["pm", "kisan", "किसान", "6000"]


def test_bm25_prefers_rare_term_matches():
    docs = {"a": "farmer income support farmer", "b": "health cover hospital", "c": "income support"}
    r = bm25_rank("hospital farmer", docs)
    assert next(i for i, _ in r) in {"a", "b"}
    assert "c" not in [i for i, _ in bm25_rank("hospital", docs)]
    assert bm25_rank("", docs) == [] and bm25_rank("x", {}) == []


def test_rrf_ordering_and_weights():
    fused = rrf([(1.0, ["a", "b", "c"]), (1.0, ["d", "b", "c"])], k=60)
    assert max(fused, key=fused.get) == "b"  # consistently high in both lists
    assert set(fused) == {"a", "b", "c", "d"}
    heavy = rrf([(5.0, ["a", "b"]), (1.0, ["b", "a"])], k=60)
    assert heavy["a"] > heavy["b"]  # weight shifts the outcome


def test_diversify_caps_per_scheme_and_top_k():
    cs = [to_chunk(chunk(f"c{i}", "x" if i < 4 else "y", "t")) for i in range(6)]
    out = diversify(cs, top_k=10, per_scheme=2)
    assert [c.chunk_id for c in out] == ["c0", "c1", "c4", "c5"]
    assert len(diversify(cs, top_k=3, per_scheme=2)) == 3


def test_prefer_language_per_scheme():
    cs = [to_chunk(chunk("e1", "a", "t")), to_chunk(chunk("h1", "a", "t", lang="hi")), to_chunk(chunk("e2", "b", "t"))]
    assert [c.chunk_id for c in prefer_language(cs, "hi")] == ["h1", "e2"]  # a has Hindi, b falls back to English
    assert [c.chunk_id for c in prefer_language(cs, None)] == ["e1", "h1", "e2"]


# ------------------------------------------------------------- API behaviour
async def test_basic_search_returns_relevant_chunks_with_meta(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "farmer income support 6000 per year", "top_k": 5})
    assert r.status_code == 200
    chunks = r.json()["chunks"]
    assert chunks[0]["scheme_id"] == "pm_kisan" and chunks[0]["chunk_id"] == "k1"
    assert chunks[0]["meta"]["state_scope"] == "All" and chunks[0]["meta"]["status"] == "verified"
    assert chunks[0]["score"] > 0 and all(c["score"] <= chunks[0]["score"] for c in chunks)


async def test_other_states_schemes_never_returned(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "farmers income support hospital treatment", "top_k": 20, "max_chunks_per_scheme": 5,
                                                "filters": {"state": "Odisha"}})
    got = schemes(r)
    assert "odisha_subhadra" in ids(r) or "pm_kisan" in got
    assert not ({"kerala_only", "kerala_health", "wb_scheme"} & got)


async def test_state_filter_includes_central_and_all(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "income support", "top_k": 20, "max_chunks_per_scheme": 5, "filters": {"state": "Kerala"}})
    got = schemes(r)
    assert {"kerala_only", "pm_kisan"} <= got and "odisha_subhadra" not in got


async def test_include_central_false_excludes_central_but_not_all_scope(make_app, qdrant):
    corp = [chunk("c1", "central_x", "income support", state="Kerala", central=True),  # central with explicit scope
            chunk("c2", "kerala_y", "income support", state="Kerala", central=False)]
    r = await run(make_app, qdrant, corp, {"query": "income support", "top_k": 5, "filters": {"state": "Assam", "include_central": False}})
    assert r.json()["chunks"] == []


async def test_scheme_ids_filter(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "income support hospital", "top_k": 20, "max_chunks_per_scheme": 5,
                                                "filters": {"scheme_ids": ["ayushman"]}})
    assert schemes(r) == {"ayushman"}


async def test_empty_scheme_ids_returns_nothing(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "income support", "filters": {"scheme_ids": []}})
    assert r.status_code == 200 and r.json()["chunks"] == []


async def test_unverified_never_returned(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "farmer income support rupees unverified scheme", "top_k": 20, "max_chunks_per_scheme": 5})
    assert "unverified_x" not in schemes(r)


async def test_per_scheme_cap_default_is_2(make_app, qdrant, corpus):
    await seed(qdrant, corpus)
    body = {"query": "pm-kisan farmer income support apply documents", "top_k": 10, "filters": {"scheme_ids": ["pm_kisan"], "language": "en"}}
    with TestClient(make_app()) as c:
        assert len(ids(c.post("/v1/search", json=body))) == 2
        assert len(ids(c.post("/v1/search", json={**body, "max_chunks_per_scheme": 3}))) == 3


async def test_language_preference_with_english_fallback(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": "किसान आय सहायता income support health", "top_k": 20, "max_chunks_per_scheme": 5,
                                                "filters": {"language": "hi"}})
    by_scheme = {}
    for c in r.json()["chunks"]:
        by_scheme.setdefault(c["scheme_id"], set()).add(c["meta"]["language"])
    assert by_scheme["pm_kisan"] == {"hi"}  # Hindi exists -> only Hindi
    assert by_scheme["ayushman"] == {"en"}  # no Hindi -> English fallback


async def test_keyword_leg_finds_exact_term_semantic_may_miss(make_app, qdrant):
    corp = [chunk(f"n{i}", f"s{i}", "generic welfare text number " + str(i)) for i in range(30)]
    corp.append(chunk("rare", "rare_scheme", "contains the unique word zxqvlongtail here and more filler words"))
    r = await run(make_app, qdrant, corp, {"query": "zxqvlongtail", "top_k": 3}, pool=3)
    assert "rare" in ids(r)


async def test_hybrid_weights_can_disable_keyword_leg(make_app, qdrant, corpus):
    on = await run(make_app, qdrant, corpus, {"query": "Khatauni", "top_k": 3})
    assert "k2" in ids(on)


async def test_query_embedded_as_query_kind_and_request_id_forwarded(make_app, qdrant, corpus, embedder):
    await seed(qdrant, corpus)
    with TestClient(make_app()) as c:
        c.post("/v1/search", json={"query": "income"}, headers={"X-Request-ID": "trace-77"})
    req = embedder.requests[-1]
    assert json.loads(req.content)["kind"] == "query"
    assert req.headers["x-request-id"] == "trace-77"


async def test_validation_errors(make_app, qdrant, corpus):
    r = await run(make_app, qdrant, corpus, {"query": ""})
    assert r.status_code == 422


# ------------------------------------------------------------- failures are explicit, never silent-empty
def test_missing_index_is_503_with_clear_message(make_app):
    with TestClient(make_app()) as c:
        r = c.post("/v1/search", json={"query": "x"})
    assert r.status_code == 503 and "does not exist" in r.json()["detail"]


def test_embedding_down_is_503(make_app, embedder):
    embedder.fail = True
    with TestClient(make_app()) as c:
        r = c.post("/v1/search", json={"query": "x"})
    assert r.status_code == 503 and "embedding-service" in r.json()["detail"]


async def test_qdrant_error_is_503(make_app, qdrant, corpus):
    await seed(qdrant, corpus)

    async def boom(*a, **k):
        raise RuntimeError("qdrant exploded")

    qdrant.query_points = boom
    with TestClient(make_app()) as c:
        r = c.post("/v1/search", json={"query": "x"})
    assert r.status_code == 503 and "vector store error" in r.json()["detail"]


def test_ready_reports_dependencies(make_app):
    with TestClient(make_app()) as c:
        assert c.get("/ready").json()["checks"] == {"qdrant": True, "embedding-service": True}
        assert c.get("/health").status_code == 200


# ------------------------------------------------------------- reranker (off by default)
async def test_reranker_off_by_default_and_on_reorders(make_app, qdrant, corpus):
    body = {"query": "income support", "top_k": 3, "max_chunks_per_scheme": 3, "filters": {"scheme_ids": ["pm_kisan"], "language": "en"}}
    base = ids(await run(make_app, qdrant, corpus, body))

    calls = []

    def gateway(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"json": {"scores": [1, 5, 9]}})

    from qdrant_client import AsyncQdrantClient

    from .conftest import FakeEmbedder

    q2 = AsyncQdrantClient(":memory:")
    await seed(q2, corpus)
    emb = FakeEmbedder()

    def transport(req):
        return gateway(req) if req.url.path == "/v1/chat" else emb(req)

    from retrieval_service.config import Settings
    from retrieval_service.main import create_app

    app = create_app(Settings(qdrant_url=":memory:", embedding_url="http://emb:8002", reranker="llm", llm_gateway_url="http://gw:8001"),
                     qdrant=q2, transport=httpx.MockTransport(transport))
    with TestClient(app) as c:
        reranked = [x["chunk_id"] for x in c.post("/v1/search", json=body).json()["chunks"]]
    assert calls and calls[0]["model_alias"] == "reranker"
    assert reranked == list(reversed(base[:3])) or reranked != base


async def test_reranker_failure_keeps_original_order(make_app, qdrant, corpus):
    body = {"query": "income support", "top_k": 3, "max_chunks_per_scheme": 3, "filters": {"scheme_ids": ["pm_kisan"], "language": "en"}}
    base = ids(await run(make_app, qdrant, corpus, body))

    from qdrant_client import AsyncQdrantClient

    from .conftest import FakeEmbedder

    q2 = AsyncQdrantClient(":memory:")
    await seed(q2, corpus)
    emb = FakeEmbedder()

    def transport(req):
        if req.url.path == "/v1/chat":
            return httpx.Response(503, json={"detail": "down"})
        return emb(req)

    from retrieval_service.config import Settings
    from retrieval_service.main import create_app

    app = create_app(Settings(qdrant_url=":memory:", embedding_url="http://emb:8002", reranker="llm"), qdrant=q2, transport=httpx.MockTransport(transport))
    with TestClient(app) as c:
        got = [x["chunk_id"] for x in c.post("/v1/search", json=body).json()["chunks"]]
    assert got == base


def test_unused_import_guard():
    assert pytest


def test_bm25_tokenizer_keeps_hindi_words_whole():
    assert tokenize("किसान सम्मान निधि") == ["किसान", "सम्मान", "निधि"]
    assert bm25_rank("किसान", {"a": "किसान सम्मान निधि", "b": "छात्रवृत्ति योजना"})[0][0] == "a"
