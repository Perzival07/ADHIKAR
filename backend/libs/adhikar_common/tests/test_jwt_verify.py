import json

import httpx
import jwt
import pytest
from adhikar_common import JWKSVerifier, TokenInvalid
from cryptography.hazmat.primitives.asymmetric import ec


def make_key(kid):
    key = ec.generate_private_key(ec.SECP256R1())
    jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(key.public_key()))
    jwk.update(kid=kid, alg="ES256", use="sig")
    return key, jwk


def token(key, kid, **over):
    import time

    claims = {"sub": "user-1", "iss": "adhikar-auth", "aud": "adhikar-api", "iat": int(time.time()), "exp": int(time.time()) + 60}
    claims.update(over)
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": kid})


class JWKS:
    def __init__(self, *jwks):
        self.keys = list(jwks)
        self.calls = 0
        self.down = False

    def __call__(self, request):
        self.calls += 1
        if self.down:
            return httpx.Response(503)
        return httpx.Response(200, json={"keys": self.keys})


def verifier(server, clock=None):
    kw = {"clock": clock} if clock else {}
    return JWKSVerifier("http://auth/.well-known/jwks.json", "adhikar-auth", "adhikar-api",
                        httpx.AsyncClient(transport=httpx.MockTransport(server)), **kw)


async def test_valid_token_and_jwks_is_cached():
    k, jwk = make_key("k1")
    srv = JWKS(jwk)
    v = verifier(srv)
    for _ in range(3):
        assert (await v.verify(token(k, "k1"))).user_id == "user-1"
    assert srv.calls == 1


@pytest.mark.parametrize("over", [{"aud": "other"}, {"iss": "evil"}, {"exp": 1}])
async def test_claims_are_enforced(over):
    k, jwk = make_key("k1")
    with pytest.raises(TokenInvalid):
        await verifier(JWKS(jwk)).verify(token(k, "k1", **over))


async def test_wrong_signature_and_garbage_rejected():
    _, jwk = make_key("k1")
    attacker, _ = make_key("k1")
    v = verifier(JWKS(jwk))
    with pytest.raises(TokenInvalid):
        await v.verify(token(attacker, "k1"))
    with pytest.raises(TokenInvalid):
        await v.verify("not.a.token")


async def test_key_rotation_refetches_once_and_is_throttled():
    t = [0.0]
    k1, j1 = make_key("k1")
    k2, j2 = make_key("k2")
    srv = JWKS(j1)
    v = verifier(srv, clock=lambda: t[0])
    await v.verify(token(k1, "k1"))
    srv.keys = [j1, j2]  # auth-service rotated
    t[0] = 40
    assert (await v.verify(token(k2, "k2"))).user_id == "user-1" and srv.calls == 2
    with pytest.raises(TokenInvalid):  # unknown kid again within 30 s: no refetch storm
        await v.verify(token(make_key("k3")[0], "k3"))
    assert srv.calls == 2


async def test_jwks_outage_uses_cached_keys_and_fails_closed_without_them():
    t = [0.0]
    k, jwk = make_key("k1")
    srv = JWKS(jwk)
    v = verifier(srv, clock=lambda: t[0])
    await v.verify(token(k, "k1"))
    srv.down = True
    t[0] = 10_000  # cache expired, refresh fails -> keep using cached keys
    assert (await v.verify(token(k, "k1"))).user_id == "user-1"
    with pytest.raises(TokenInvalid, match="cannot fetch"):
        await verifier(srv).verify(token(k, "k1"))  # cold start with no keys -> reject (fail closed)
