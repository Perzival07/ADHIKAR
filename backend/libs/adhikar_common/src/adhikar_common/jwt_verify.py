"""Verify access tokens issued by auth-service using its published JWKS (no shared secrets between services)."""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass

import httpx
import jwt

log = logging.getLogger("adhikar_common.jwt")


class TokenInvalid(Exception):
    pass


@dataclass
class Principal:
    user_id: str
    claims: dict


class JWKSVerifier:
    """Caches the JWKS (default 10 min). An unknown `kid` (key rotation) triggers one refetch, at most every 30 s."""

    def __init__(self, jwks_url: str, issuer: str, audience: str, client: httpx.AsyncClient | None = None,
                 cache_seconds: int = 600, clock=time.monotonic):
        self.jwks_url, self.issuer, self.audience = jwks_url, issuer, audience
        self.client = client or httpx.AsyncClient(timeout=5.0)
        self.cache_seconds, self._clock = cache_seconds, clock
        self._keys: dict[str, jwt.PyJWK] = {}
        self._fetched_at = -1e9
        self._last_forced = -1e9

    async def _refresh(self) -> None:
        r = await self.client.get(self.jwks_url)
        r.raise_for_status()
        keys = {}
        for k in r.json().get("keys", []):
            if k.get("kid") and k.get("alg", "ES256") == "ES256":
                keys[k["kid"]] = jwt.PyJWK(k)
        self._keys, self._fetched_at = keys, self._clock()

    async def _key(self, kid: str) -> jwt.PyJWK:
        now = self._clock()
        try:
            if now - self._fetched_at > self.cache_seconds:
                await self._refresh()
            if kid not in self._keys and now - self._last_forced > 30:
                self._last_forced = now
                await self._refresh()
        except (httpx.HTTPError, ValueError) as e:
            if not self._keys:
                raise TokenInvalid(f"cannot fetch signing keys: {e.__class__.__name__}") from e
            log.warning("JWKS refresh failed; using cached keys")
        if kid not in self._keys:
            raise TokenInvalid("unknown signing key")
        return self._keys[kid]

    async def verify(self, token: str) -> Principal:
        try:
            kid = jwt.get_unverified_header(token).get("kid", "")
            key = await self._key(kid)
            claims = jwt.decode(token, key.key, algorithms=["ES256"], issuer=self.issuer, audience=self.audience,
                                options={"require": ["exp", "iat", "sub", "iss", "aud"]})
        except jwt.PyJWTError as e:
            raise TokenInvalid(str(e)) from e
        return Principal(user_id=str(claims["sub"]), claims=claims)
