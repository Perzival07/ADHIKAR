import asyncio
import json

import httpx
import pytest
import yaml
from fastapi.testclient import TestClient

from llm_gateway.config import Settings
from llm_gateway.main import create_app

SCHEMA = {
    "type": "object",
    "properties": {"answer": {"type": "string"}, "n": {"type": "integer", "minimum": 1}},
    "required": ["answer", "n"],
}


def make_app(tmp_path, aliases, transport=None, **settings):
    f = tmp_path / "models.yaml"
    f.write_text(yaml.safe_dump({"aliases": aliases}))
    return create_app(Settings(models_file=str(f), **settings), transport=transport)


def body(alias="a", **kw):
    return {"model_alias": alias, "messages": [{"role": "user", "content": "hi"}], **kw}


def ollama_transport(handler):
    return httpx.MockTransport(handler)


def ollama_reply(content):
    return httpx.Response(200, json={"message": {"content": content}, "prompt_eval_count": 3, "eval_count": 2})


# ------------------------------------------------------------------ routing
def test_alias_routing_and_models(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock", "model": "m1"}, "b": {"provider": "mock"}}))
    r = c.post("/v1/chat", json=body("a"))
    assert r.status_code == 200
    d = r.json()
    assert d["provider"] == "mock" and d["model"] == "m1" and d["text"].startswith("Mock response")
    assert d["json"] is None
    aliases = {a["alias"] for a in c.get("/v1/models").json()["aliases"]}
    assert aliases == {"a", "b"}


def test_unknown_alias_404(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    r = c.post("/v1/chat", json=body("nope"))
    assert r.status_code == 404 and "nope" in r.json()["detail"]


def test_unknown_provider_fails_at_startup(tmp_path):
    with pytest.raises(ValueError):
        make_app(tmp_path, {"a": {"provider": "skynet"}})


# ------------------------------------------------------------------ json mode
def test_json_schema_mock_valid(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    d = c.post("/v1/chat", json=body(json_schema=SCHEMA)).json()
    assert d["json"] == {"answer": "mock", "n": 1}


def test_json_repair_succeeds_on_second_try(tmp_path):
    calls = []

    def handler(request):
        payload = json.loads(request.content)
        calls.append(payload)
        if len(calls) == 1:
            return ollama_reply('{"answer": "x"}')  # missing n
        return ollama_reply('```json\n{"answer": "x", "n": 2}\n```')

    c = TestClient(make_app(tmp_path, {"a": {"provider": "ollama", "model": "m"}}, ollama_transport(handler)))
    r = c.post("/v1/chat", json=body(json_schema=SCHEMA))
    assert r.status_code == 200 and r.json()["json"] == {"answer": "x", "n": 2}
    assert len(calls) == 2
    repair_prompt = calls[1]["messages"][-1]["content"]
    assert "rejected" in repair_prompt and "'n' is a required property" in repair_prompt
    assert r.json()["usage"]["prompt_tokens"] == 6  # both calls counted


def test_json_repair_fails_422_with_raw(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock", "mode": "invalid_json"}}))
    r = c.post("/v1/chat", json=body(json_schema=SCHEMA))
    assert r.status_code == 422
    assert r.json()["raw"] == "this is not json {"


# ------------------------------------------------------------------ adapters
def test_ollama_request_mapping(tmp_path):
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["json"] = json.loads(request.content)
        return ollama_reply('{"answer":"ok","n":1}')

    app = make_app(
        tmp_path,
        {"a": {"provider": "ollama", "model": "tiny", "base_url": "http://ollama:11434",
               "options": {"num_ctx": 4096, "num_gpu": 99, "keep_alive": "30m", "ignored": 1}}},
        ollama_transport(handler),
    )
    c = TestClient(app)
    c.post("/v1/chat", json=body(json_schema=SCHEMA, max_tokens=50, temperature=0.1))
    assert seen["url"] == "http://ollama:11434/api/chat"
    j = seen["json"]
    assert j["model"] == "tiny" and j["format"] == SCHEMA and j["stream"] is False
    assert j["options"] == {"num_ctx": 4096, "num_gpu": 99, "num_predict": 50, "temperature": 0.1}
    assert j["keep_alive"] == "30m"


def test_openai_compatible_mapping_and_instruction_fallback(tmp_path):
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["json"] = json.loads(request.content)
        return httpx.Response(
            200, json={"choices": [{"message": {"content": '{"answer":"a","n":1}'}}], "usage": {"prompt_tokens": 5, "completion_tokens": 4}}
        )

    # supports_json_schema false -> schema injected as an instruction, no response_format
    c = TestClient(make_app(tmp_path, {"a": {"provider": "openai_compatible", "model": "m", "base_url": "http://x:8080"}}, httpx.MockTransport(handler)))
    r = c.post("/v1/chat", json=body(json_schema=SCHEMA))
    assert r.status_code == 200 and r.json()["usage"] == {"prompt_tokens": 5, "completion_tokens": 4}
    assert seen["url"] == "http://x:8080/v1/chat/completions"
    assert "response_format" not in seen["json"]
    assert seen["json"]["messages"][0]["role"] == "system" and "JSON Schema" in seen["json"]["messages"][0]["content"]

    # supports_json_schema true -> native response_format
    c = TestClient(make_app(tmp_path, {"a": {"provider": "openai_compatible", "model": "m", "base_url": "http://x:8080", "options": {"supports_json_schema": True}}}, httpx.MockTransport(handler)))
    c.post("/v1/chat", json=body(json_schema=SCHEMA))
    assert seen["json"]["response_format"]["json_schema"]["schema"] == SCHEMA
    assert seen["json"]["messages"][0]["role"] == "user"


# ------------------------------------------------------------------ errors / fallback
def test_timeout_maps_to_504(tmp_path):
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    c = TestClient(make_app(tmp_path, {"a": {"provider": "ollama", "model": "m"}}, httpx.MockTransport(handler)))
    assert c.post("/v1/chat", json=body()).status_code == 504


def test_unreachable_maps_to_503_and_fallback_chain(tmp_path):
    def handler(request):
        raise httpx.ConnectError("down", request=request)

    aliases = {"a": {"provider": "ollama", "model": "m", "fallback": ["safe"]}, "safe": {"provider": "mock"}, "solo": {"provider": "ollama", "model": "m"}}
    c = TestClient(make_app(tmp_path, aliases, httpx.MockTransport(handler)))
    assert c.post("/v1/chat", json=body("solo")).status_code == 503
    r = c.post("/v1/chat", json=body("a"))
    assert r.status_code == 200 and r.json()["provider"] == "mock"


def test_bad_fallback_alias_rejected(tmp_path):
    with pytest.raises(ValueError):
        make_app(tmp_path, {"a": {"provider": "mock", "fallback": ["ghost"]}})


def test_ready_false_when_model_server_down_but_service_up(tmp_path):
    def handler(request):
        raise httpx.ConnectError("down", request=request)

    c = TestClient(make_app(tmp_path, {"a": {"provider": "ollama", "model": "m"}, "m": {"provider": "mock"}}, httpx.MockTransport(handler)))
    assert c.get("/health").status_code == 200
    r = c.get("/ready")
    assert r.status_code == 503 and r.json()["checks"] == {"a": False, "m": True}


# ------------------------------------------------------------------ streaming
def _events(text):
    out, ev = [], None
    for line in text.splitlines():
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:"):
            out.append((ev or "message", json.loads(line[5:].strip())))
            ev = None
    return out


def test_streaming_sse_format_mock(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    r = c.post("/v1/chat", json=body(stream=True))
    assert r.headers["content-type"].startswith("text/event-stream")
    evs = _events(r.text)
    deltas = [e[1]["delta"] for e in evs if e[0] == "message"]
    assert "".join(deltas).startswith("Mock response to: hi")
    assert evs[-1][0] == "done" and evs[-1][1]["provider"] == "mock"


def test_streaming_ollama_ndjson_to_sse(tmp_path):
    def handler(request):
        lines = [
            {"message": {"content": "Hel"}, "done": False},
            {"message": {"content": "lo"}, "done": False},
            {"message": {"content": ""}, "done": True},
        ]
        return httpx.Response(200, content="\n".join(json.dumps(x) for x in lines).encode())

    c = TestClient(make_app(tmp_path, {"a": {"provider": "ollama", "model": "m"}}, httpx.MockTransport(handler)))
    evs = _events(c.post("/v1/chat", json=body(stream=True)).text)
    assert [e[1]["delta"] for e in evs if e[0] == "message"] == ["Hel", "lo"]


def test_streaming_unknown_alias_404(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    assert c.post("/v1/chat", json=body("zzz", stream=True)).status_code == 404


# ------------------------------------------------------------------ concurrency
async def test_queue_full_returns_429(tmp_path):
    app = make_app(tmp_path, {"a": {"provider": "mock", "mode": "slow", "options": {"delay": 0.3}}}, concurrency=1, queue_max=1)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        rs = await asyncio.gather(*(c.post("/v1/chat", json=body()) for _ in range(4)))
    codes = sorted(r.status_code for r in rs)
    assert codes.count(200) >= 2 and 429 in codes  # 1 running + 1 queued, rest rejected


async def test_concurrency_one_serialises(tmp_path):
    running, peak = 0, 0

    async def handler_async():
        pass

    app = make_app(tmp_path, {"a": {"provider": "mock", "mode": "slow", "options": {"delay": 0.05}}}, concurrency=1, queue_max=10)
    provider = app.state.gateway.registry.entries["a"].provider
    orig = provider.chat

    async def tracked(req):
        nonlocal running, peak
        running += 1
        peak = max(peak, running)
        try:
            return await orig(req)
        finally:
            running -= 1

    provider.chat = tracked
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        rs = await asyncio.gather(*(c.post("/v1/chat", json=body()) for _ in range(5)))
    assert all(r.status_code == 200 for r in rs) and peak == 1


# ------------------------------------------------------------------ misc
def test_request_id_propagated(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    assert c.post("/v1/chat", json=body(), headers={"X-Request-ID": "rid-9"}).headers["x-request-id"] == "rid-9"


def test_mock_echoes_schemes_in_prompt_order(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    schema = {
        "type": "object",
        "properties": {"recommendations": {"type": "array", "items": {"$ref": "#/$defs/R"}}},
        "required": ["recommendations"],
        "$defs": {"R": {"type": "object", "properties": {
            "scheme_id": {"type": "string"}, "rank": {"type": "integer", "minimum": 1},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1}, "reason": {"type": "string"},
            "citations": {"type": "array", "items": {"type": "object", "properties": {"chunk_id": {"type": "string"}}, "required": ["chunk_id"]}}},
            "required": ["scheme_id", "rank", "confidence", "reason"]}},
    }
    prompt = '<doc id="c1" scheme="pm_kisan">x</doc><doc id="c2" scheme="ayushman">y</doc><doc id="c3" scheme="pm_kisan">z</doc>'
    r = c.post("/v1/chat", json={"model_alias": "a", "messages": [{"role": "user", "content": prompt}], "json_schema": schema})
    recs = r.json()["json"]["recommendations"]
    assert [x["scheme_id"] for x in recs] == ["pm_kisan", "ayushman"]
    assert [x["rank"] for x in recs] == [1, 2]
    assert recs[0]["citations"][0]["chunk_id"] == "c1"


def test_no_message_content_in_info_logs(tmp_path, capsys):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    c.post("/v1/chat", json={"model_alias": "a", "messages": [{"role": "user", "content": "SECRET-INCOME-DATA"}]})
    assert "SECRET-INCOME-DATA" not in capsys.readouterr().out


# ------------------------------------------------------------------ metrics
def test_metrics_endpoint_counts_requests_tokens_repairs_and_failures(tmp_path):
    calls = []

    def handler(request):
        calls.append(1)
        return ollama_reply('{"answer": "x"}' if len(calls) == 1 else '{"answer": "x", "n": 1}')

    c = TestClient(make_app(tmp_path, {"a": {"provider": "ollama", "model": "m"}, "dead": {"provider": "mock", "mode": "error"}}, ollama_transport(handler)))
    c.post("/v1/chat", json=body("a", json_schema=SCHEMA))  # needs one repair
    c.post("/v1/chat", json=body("dead"))  # mock "error" mode = provider failure
    text = c.get("/metrics").text
    assert 'llmgw_requests_total{alias="a",provider="ollama",outcome="ok"} 1' in text
    assert 'llmgw_requests_total{alias="dead",provider="-",outcome="provider_error"} 1' in text
    assert 'llmgw_json_repairs_total{alias="a"} 1' in text
    assert 'llmgw_tokens_total{alias="a",kind="prompt"} 6' in text and 'llmgw_tokens_total{alias="a",kind="completion"} 4' in text
    assert 'llmgw_provider_failures_total{alias="dead",provider="mock"} 1' in text
    assert 'adhikar_http_requests_total{service="llm-gateway",method="POST",route="/v1/chat",status="200"} 1' in text
    assert "/metrics" not in text.replace("# ", "") or 'route="/metrics"' not in text


async def test_queue_rejections_are_counted(tmp_path):
    app = make_app(tmp_path, {"a": {"provider": "mock", "mode": "slow", "options": {"delay": 0.3}}}, concurrency=1, queue_max=0)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        await asyncio.gather(*(c.post("/v1/chat", json=body()) for _ in range(3)))
        text = (await c.get("/metrics")).text
    assert "llmgw_queue_rejections_total 2" in text and 'outcome="queue_full"' in text


def test_mock_cites_the_first_document_for_explain_style_schemas(tmp_path):
    c = TestClient(make_app(tmp_path, {"a": {"provider": "mock"}}))
    schema = {"type": "object", "required": ["explanation"], "properties": {
        "explanation": {"type": "string"},
        "citations": {"type": "array", "items": {"type": "object", "required": ["chunk_id"], "properties": {"chunk_id": {"type": "string"}, "quote": {"type": "string"}}}}}}
    prompt = '<doc id="c9" scheme="pm_kisan">x</doc><doc id="c10" scheme="pm_kisan">y</doc>'
    r = c.post("/v1/chat", json={"model_alias": "a", "messages": [{"role": "user", "content": prompt}], "json_schema": schema})
    assert r.json()["json"]["citations"] == [{"chunk_id": "c9"}]


def test_mock_ignores_doc_tag_examples_in_system_prompts(tmp_path):
    from llm_gateway.providers.schema_builder import extract_schemes

    msgs = [{"role": "system", "content": 'Docs look like <doc id="..." scheme="...">'},
            {"role": "user", "content": '<doc id="c1" scheme="real_scheme">x</doc>'}]
    assert extract_schemes(msgs) == [{"scheme_id": "real_scheme", "chunk_ids": ["c1"]}]
