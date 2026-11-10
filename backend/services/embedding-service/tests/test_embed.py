import math

import httpx
import pytest
from fastapi.testclient import TestClient

from embedding_service.config import Settings
from embedding_service.main import create_app


def cos(a, b):
    return sum(x * y for x, y in zip(a, b, strict=True))


def client(**kw):
    return TestClient(create_app(Settings(**kw)))


def embed(c, texts, kind="document"):
    r = c.post("/v1/embed", json={"texts": texts, "kind": kind})
    assert r.status_code == 200, r.text
    return r.json()


def test_hash_is_deterministic_normalised_and_dimmed():
    c = client(hash_dim=128)
    a = embed(c, ["PM Kisan farmer income support"])
    b = embed(c, ["PM Kisan farmer income support"])
    assert a["vectors"] == b["vectors"]
    assert a["dim"] == 128 and len(a["vectors"][0]) == 128
    assert math.isclose(math.sqrt(sum(x * x for x in a["vectors"][0])), 1.0, rel_tol=1e-6)
    assert a["model_id"] == "hash-128"


def test_similar_texts_closer_than_unrelated():
    c = client()
    v = embed(c, ["farmer income support scheme for landholding farmers",
                  "income support for small farmers with land",
                  "scholarship for girl students in higher education"])["vectors"]
    assert cos(v[0], v[1]) > cos(v[0], v[2]) + 0.1


def test_works_on_hindi_text():
    c = client()
    v = embed(c, ["किसान सम्मान निधि योजना", "किसान सम्मान निधि", "छात्रवृत्ति योजना लड़कियां"])["vectors"]
    assert cos(v[0], v[1]) > cos(v[0], v[2])


def test_batching_keeps_order_and_count():
    c = client(batch_size=3)
    texts = [f"text number {i} unique{i}" for i in range(10)]
    batched = embed(c, texts)["vectors"]
    singles = [embed(c, [t])["vectors"][0] for t in texts]
    assert batched == singles


def test_truncation_flags_are_explicit():
    c = client(max_input_chars=20)
    d = embed(c, ["short", "x" * 100])
    assert d["truncated"] == [False, True]
    # truncated text embeds like its prefix
    assert d["vectors"][1] == embed(c, ["x" * 20])["vectors"][0]


def test_validation_rejects_empty_list():
    assert client().post("/v1/embed", json={"texts": []}).status_code == 422


def test_unknown_provider_fails_fast():
    with pytest.raises(ValueError):
        create_app(Settings(provider="magic"))


def test_sentence_transformers_not_ready_without_local_model():
    c = client(provider="sentence_transformers", model_path="/definitely/not/here")
    r = c.get("/ready")
    assert r.status_code == 503 and "does not exist" in r.json()["checks"]["sentence_transformers"]
    assert c.get("/health").status_code == 200  # service itself still up
    assert c.post("/v1/embed", json={"texts": ["x"]}).status_code == 503


def test_sentence_transformers_unset_path_message():
    r = client(provider="sentence_transformers").get("/ready")
    assert r.status_code == 503 and "EMBED_MODEL_PATH" in r.json()["checks"]["sentence_transformers"]


def test_ollama_provider_with_prefix_and_model_id():
    seen = {}

    def handler(request):
        import json

        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"embeddings": [[0.1, 0.2, 0.3] for _ in seen["body"]["input"]]})

    app = create_app(
        Settings(provider="ollama", ollama_model="bge-m3:latest", ollama_base_url="http://o:11434", query_prefix="query: "),
        transport=httpx.MockTransport(handler),
    )
    c = TestClient(app)
    d = embed(c, ["hello"], kind="query")
    assert seen["body"] == {"model": "bge-m3:latest", "input": ["query: hello"]}
    assert d["dim"] == 3 and d["model_id"] == "ollama-bge-m3_latest-3"


def test_ollama_down_gives_503():
    def handler(request):
        raise httpx.ConnectError("down", request=request)

    c = TestClient(create_app(Settings(provider="ollama", ollama_model="m"), transport=httpx.MockTransport(handler)))
    assert c.post("/v1/embed", json={"texts": ["x"]}).status_code == 503
    assert c.get("/ready").status_code == 503


def test_default_provider_is_hash():
    assert Settings().provider == "hash"


def test_indic_words_are_not_split_into_fragments():
    from embedding_service.providers.hash_provider import _TOKEN

    assert _TOKEN.findall("किसान सम्मान निधि, योजना!") == ["किसान", "सम्मान", "निधि", "योजना"]
    assert _TOKEN.findall("ਪੰਜਾਬੀ தமிழ் తెలుగు اُردُو") == ["ਪੰਜਾਬੀ", "தமிழ்", "తెలుగు", "اُردُو"]
