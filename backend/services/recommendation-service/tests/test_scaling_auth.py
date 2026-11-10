import asyncio
import json
import time

import fakeredis.aioredis
import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from recommendation_service.config import Settings
from recommendation_service.main import create_app

from .conftest import PROFILE


def settings(**kw):
    base = {"eligibility_url": "http://elig:8005", "retrieval_url": "http://ret:8004", "llm_gateway_url": "http://llm:8001",
            "auth_jwks_url": "http://auth:8006/.well-known/jwks.json"}
    base.update(kw)
    return Settings(**base)


class Issuer:
    """Stands in for auth-service: signs ES256 tokens and serves the JWKS."""

    def __init__(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(self.key.public_key()))
        jwk.update(kid="k1", alg="ES256", use="sig")
        self.jwks = {"keys": [jwk]}

    def token(self, sub="user-1", **over):
        now = int(time.time())
        claims = {"sub": sub, "iss": "adhikar-auth", "aud": "adhikar-api", "iat": now, "exp": now + 300, **over}
        return jwt.encode(claims, self.key, algorithm="ES256", headers={"kid": "k1"})


@pytest.fixture
def issuer():
    return Issuer()


@pytest.fixture
def transport(stack, issuer):
    def route(request):
        if request.url.port == 8006:
            return httpx.Response(200, json=issuer.jwks)
        return stack(request)

    return httpx.MockTransport(route)


def body():
    return {"profile": PROFILE}


# ------------------------------------------------------------------ horizontal scaling: shared state
def test_two_replicas_share_the_response_cache(stack, transport):
    redis = fakeredis.aioredis.FakeRedis()
    a = TestClient(create_app(settings(), transport=transport, redis=redis))
    b = TestClient(create_app(settings(), transport=transport, redis=redis))
    with a, b:
        assert a.post("/v1/recommendations", json=body()).status_code == 200
        assert b.post("/v1/recommendations", json=body()).json()["mode"] == "rag"
    assert len(stack.llm_calls) == 1  # replica B answered from the shared cache


def test_cache_clear_on_one_replica_applies_to_all(stack, transport):
    redis = fakeredis.aioredis.FakeRedis()
    a = TestClient(create_app(settings(admin_token="t"), transport=transport, redis=redis))
    b = TestClient(create_app(settings(), transport=transport, redis=redis))
    with a, b:
        a.post("/v1/recommendations", json=body())
        a.post("/v1/admin/cache/clear", headers={"Authorization": "Bearer t"})
        b.post("/v1/recommendations", json=body())
    assert len(stack.llm_calls) == 2


def test_rate_limit_is_shared_across_replicas(stack, transport):
    redis = fakeredis.aioredis.FakeRedis()
    a = TestClient(create_app(settings(rate_limit_per_minute=3, cache_ttl=0), transport=transport, redis=redis))
    b = TestClient(create_app(settings(rate_limit_per_minute=3, cache_ttl=0), transport=transport, redis=redis))
    with a, b:
        codes = [c.post("/v1/recommendations", json=body()).status_code for c in (a, b, a, b, a)]
    assert codes == [200, 200, 200, 429, 429]


async def test_concurrent_identical_requests_are_coalesced(stack, transport):
    app = create_app(settings(cache_ttl=0), transport=transport, redis=fakeredis.aioredis.FakeRedis())
    gate = asyncio.Event()
    orig = app.state.pipeline.clients.chat

    async def slow_chat(*a, **k):
        await gate.wait()
        return await orig(*a, **k)

    app.state.pipeline.clients.chat = slow_chat
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        reqs = [asyncio.create_task(c.post("/v1/recommendations", json=body(), headers={"X-Request-ID": f"r{i}"})) for i in range(8)]
        for _ in range(50):
            await asyncio.sleep(0.01)
            if app.state.pipeline.flight.in_flight == 1 and len(stack.elig_calls) == 1:
                break
        gate.set()
        rs = await asyncio.gather(*reqs)
    assert all(r.status_code == 200 for r in rs)
    assert len(stack.llm_calls) == 1 and len(stack.elig_calls) == 1  # 8 users, one pipeline run
    assert sorted(r.json()["trace_id"] for r in rs) == sorted(f"r{i}" for i in range(8))  # each keeps its own trace id
    assert app.state.metrics.c["coalesced_total"] == 7


async def test_coalesced_failure_reaches_every_waiter(stack, transport):
    stack.elig_down = True
    app = create_app(settings(cache_ttl=0), transport=transport, redis=fakeredis.aioredis.FakeRedis())
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        rs = await asyncio.gather(*(c.post("/v1/recommendations", json=body()) for _ in range(4)))
    assert {r.status_code for r in rs} == {503} and app.state.pipeline.flight.in_flight == 0


def test_redis_outage_degrades_gracefully(stack, transport):
    class Down:
        def __getattr__(self, name):
            raise ConnectionError("redis down")

    with TestClient(create_app(settings(), transport=transport, redis=Down())) as c:
        r = c.post("/v1/recommendations", json=body())
    assert r.status_code == 200 and r.json()["mode"] == "rag"  # no cache, no shared limits, but still serving


# ------------------------------------------------------------------ authentication modes
def test_optional_mode_accepts_anonymous_and_valid_tokens_rejects_bad_ones(stack, transport, issuer):
    with TestClient(create_app(settings(auth_mode="optional"), transport=transport)) as c:
        assert c.post("/v1/recommendations", json=body()).status_code == 200
        assert c.post("/v1/recommendations", json=body(), headers={"Authorization": f"Bearer {issuer.token()}"}).status_code == 200
        bad = c.post("/v1/recommendations", json=body(), headers={"Authorization": f"Bearer {issuer.token(aud='x')}"})
        assert bad.status_code == 401 and bad.headers["www-authenticate"] == "Bearer"
        forged = Issuer().token()  # signed by a different key with the same kid
        assert c.post("/v1/recommendations", json=body(), headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_required_mode(stack, transport, issuer):
    with TestClient(create_app(settings(auth_mode="required"), transport=transport)) as c:
        r = c.post("/v1/recommendations", json=body())
        assert r.status_code == 401 and r.json()["detail"] == "Sign in required."
        assert c.post("/v1/explain", json={"profile": PROFILE, "scheme_id": "pm_kisan"}).status_code == 401
        ok = c.post("/v1/recommendations", json=body(), headers={"Authorization": f"Bearer {issuer.token()}"})
        assert ok.status_code == 200
        assert c.get("/health").status_code == 200  # probes never need auth


def test_off_mode_ignores_tokens(stack, transport):
    with TestClient(create_app(settings(auth_mode="off"), transport=transport)) as c:
        assert c.post("/v1/recommendations", json=body(), headers={"Authorization": "Bearer junk"}).status_code == 200


def test_invalid_auth_mode_fails_fast():
    with pytest.raises(ValueError):
        create_app(settings(auth_mode="sometimes"))


def test_signed_in_users_get_their_own_larger_quota(stack, transport, issuer):
    with TestClient(create_app(settings(rate_limit_per_minute=1, rate_limit_per_minute_user=3, cache_ttl=0), transport=transport)) as c:
        anon = [c.post("/v1/recommendations", json=body()).status_code for _ in range(2)]
        h1 = {"Authorization": f"Bearer {issuer.token('alice')}"}
        h2 = {"Authorization": f"Bearer {issuer.token('bob')}"}
        alice = [c.post("/v1/recommendations", json=body(), headers=h1).status_code for _ in range(4)]
        bob = c.post("/v1/recommendations", json=body(), headers=h2).status_code
    assert anon == [200, 429] and alice == [200, 200, 200, 429] and bob == 200
