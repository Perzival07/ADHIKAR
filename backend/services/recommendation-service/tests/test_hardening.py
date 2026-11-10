import json

import httpx
import pytest
from fastapi.testclient import TestClient

from recommendation_service.config import Settings
from recommendation_service.main import create_app

from .conftest import PROFILE, FakeStack, chunk


def post(c, **kw):
    return c.post("/v1/recommendations", json={"profile": PROFILE, **kw})


# ------------------------------------------------------------------ circuit breaker
def test_llm_breaker_opens_then_fails_fast_then_recovers(make_app, stack):
    stack.llm_mode = "http503"
    app = make_app(breaker_threshold=3, cache_ttl=0)
    with TestClient(app) as c:
        reasons = [post(c).json()["fallback_reason"] for _ in range(3)]
        assert reasons == ["llm_503"] * 3 and len(stack.llm_calls) == 3
        d = post(c).json()
        assert d["fallback_reason"] == "llm_circuit_open" and d["mode"] == "rules_only"
        assert len(stack.llm_calls) == 3  # fail fast: the dependency was NOT called
        assert c.app.state.metrics.c["circuit_open_total"] == 1

        # time passes -> half-open -> one trial call; a healthy answer closes the circuit
        br = app.state.pipeline.clients.breakers["llm-gateway"]
        br.opened_at -= 100
        stack.llm_mode = "ok"
        assert post(c).json()["mode"] == "rag" and br.state == "closed"
        assert len(stack.llm_calls) == 4


def test_failed_trial_reopens_the_circuit(make_app, stack):
    stack.llm_mode = "http503"
    app = make_app(breaker_threshold=2, cache_ttl=0)
    with TestClient(app) as c:
        post(c)
        post(c)
        br = app.state.pipeline.clients.breakers["llm-gateway"]
        assert br.state == "open"
        br.opened_at -= 100
        assert post(c).json()["fallback_reason"] == "llm_503"  # trial hits the still-broken dependency
        assert br.state == "open" and post(c).json()["fallback_reason"] == "llm_circuit_open"


def test_busy_429_does_not_open_the_circuit(make_app, stack):
    stack.llm_mode = "http429"
    app = make_app(breaker_threshold=3, cache_ttl=0)
    with TestClient(app) as c:
        for _ in range(6):
            assert post(c).json()["fallback_reason"] == "llm_429"
        assert len(stack.llm_calls) == 6
        assert app.state.pipeline.clients.breakers["llm-gateway"].state == "closed"


def test_breakers_are_independent_per_service(make_app, stack):
    stack.llm_mode = "http503"
    app = make_app(breaker_threshold=2, cache_ttl=0)
    with TestClient(app) as c:
        post(c)
        post(c)
        b = app.state.pipeline.clients.breakers
        assert b["llm-gateway"].state == "open" and b["eligibility-service"].state == "closed" and b["retrieval-service"].state == "closed"


def test_eligibility_breaker_gives_clear_503(make_app, stack):
    stack.elig_down = True
    app = make_app(breaker_threshold=2, cache_ttl=0)
    with TestClient(app) as c:
        assert post(c).status_code == 503 and post(c).status_code == 503
        r = post(c)
        assert r.status_code == 503 and "circuit open" in r.json()["detail"] and len(stack.elig_calls) == 2


def test_timeouts_count_as_failures(make_app, stack):
    stack.llm_mode = "timeout"
    app = make_app(breaker_threshold=2, cache_ttl=0)
    with TestClient(app) as c:
        assert [post(c).json()["fallback_reason"] for _ in range(3)] == ["llm_504", "llm_504", "llm_circuit_open"]


# ------------------------------------------------------------------ request body limit
def test_oversized_body_is_rejected_with_413(make_app):
    with TestClient(make_app(max_body_bytes=2048)) as c:
        big = {"profile": PROFILE, "language": "en", "pad": "x" * 5000}
        r = c.post("/v1/recommendations", json=big)
        assert r.status_code == 413 and "too large" in r.json()["detail"]
        assert post(c).status_code == 200  # normal bodies are fine


def test_chunked_body_without_content_length_is_also_limited(make_app):
    def gen():
        for _ in range(10):
            yield b'{"profile": {}, "x": "' + b"a" * 500 + b'"}'

    with TestClient(make_app(max_body_bytes=2048)) as c:
        r = c.post("/v1/recommendations", content=gen(), headers={"content-type": "application/json"})
    assert r.status_code == 413


def test_body_limit_only_applies_to_v1(make_app):
    with TestClient(make_app(max_body_bytes=10)) as c:
        assert c.get("/health").status_code == 200


# ------------------------------------------------------------------ metrics endpoint
def test_metrics_expose_pipeline_and_http_series(make_app, stack):
    stack.llm_mode = "hallucinate"
    with TestClient(make_app(cache_ttl=0)) as c:
        post(c)
        stack.llm_mode = "http503"
        post(c)
        text = c.get("/metrics").text
    assert "reco_requests_total 2" in text
    assert "reco_hallucinated_schemes_dropped_total 1" in text
    assert "reco_fallback_total 1" in text and "reco_fallback_reason_llm_503_total 1" in text
    assert "reco_llm_items_total" in text and "reco_mode_rag_total 1" in text
    for stage in ("eligibility", "retrieval", "llm"):
        assert f'reco_stage_seconds_count{{stage="{stage}"}}' in text
    assert 'haqdaar_http_requests_total{service="recommendation-service",method="POST",route="/v1/recommendations",status="200"} 2' in text


def test_metrics_hidden_from_openapi_and_protected_by_token(make_app):
    with TestClient(make_app(metrics_token="s3cret")) as c:
        assert "/metrics" not in c.get("/openapi.json").json()["paths"]
        assert c.get("/metrics").status_code == 401
        assert c.get("/metrics", headers={"Authorization": "Bearer wrong"}).status_code == 401
        assert c.get("/metrics", headers={"Authorization": "Bearer s3cret"}).status_code == 200


def test_metrics_contain_no_profile_data(make_app):
    with TestClient(make_app()) as c:
        post(c)
        text = c.get("/metrics").text
    for secret in ("Antyodaya", "Divyangjan", "OBC", "Uttar Pradesh", "< 1 Lakh"):
        assert secret not in text


@pytest.mark.parametrize("unused", [None])
def test_guard_imports(unused):
    assert json and httpx and Settings and create_app and FakeStack and chunk


# ------------------------------------------------------------------ rate limiter identity + memory
def _hdr(ip):
    return {"X-Forwarded-For": ip}


def test_rate_limit_ignores_forwarded_header_unless_trusted(make_app):
    with TestClient(make_app(rate_limit_per_minute=2, cache_ttl=0)) as c:  # not trusted: spoofing must not help
        codes = [c.post("/v1/recommendations", json={"profile": PROFILE}, headers=_hdr(f"1.1.1.{i}")).status_code for i in range(4)]
    assert codes == [200, 200, 429, 429]


def test_rate_limit_is_per_forwarded_client_when_behind_a_trusted_proxy(make_app):
    with TestClient(make_app(rate_limit_per_minute=2, cache_ttl=0, trust_forwarded_for=True)) as c:
        def hit(ip):
            return c.post("/v1/recommendations", json={"profile": PROFILE}, headers=_hdr(ip)).status_code

        assert [hit("10.0.0.1"), hit("10.0.0.1"), hit("10.0.0.1")] == [200, 200, 429]
        assert hit("10.0.0.2") == 200  # a different user behind the same proxy is unaffected
        assert hit("10.0.0.9, 172.16.0.1") == 200  # first hop is the client


# ------------------------------------------------------------------ cache invalidation
def test_admin_cache_clear_requires_token_and_refreshes_results(make_app, stack):
    with TestClient(make_app(admin_token="adm")) as c:
        post(c)
        post(c)
        assert len(stack.llm_calls) == 1  # cached
        assert c.post("/v1/admin/cache/clear").status_code == 401
        assert c.post("/v1/admin/cache/clear", headers={"Authorization": "Bearer nope"}).status_code == 401
        assert c.post("/v1/admin/cache/clear", headers={"Authorization": "Bearer adm"}).status_code == 200
        post(c)
        assert len(stack.llm_calls) == 2  # recomputed with fresh data
        assert "/v1/admin/cache/clear" not in c.get("/openapi.json").json()["paths"]


def test_admin_endpoint_is_disabled_without_a_token(make_app):
    with TestClient(make_app()) as c:
        assert c.post("/v1/admin/cache/clear").status_code == 404
        assert c.post("/v1/admin/cache/clear", headers={"Authorization": "Bearer "}).status_code == 404


def test_default_cache_ttl_is_short():
    assert Settings().cache_ttl <= 120
