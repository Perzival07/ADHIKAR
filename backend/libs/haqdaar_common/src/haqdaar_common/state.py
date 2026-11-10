"""Shared state for horizontally scaled services: response cache + rate limiter.

Redis-backed in production (state shared by every replica); in-memory for local dev and tests.
Both FAIL OPEN if Redis is unreachable: a cache miss / an allowed request is better than an outage.
"""
from __future__ import annotations

import logging
import time
from collections import OrderedDict
from typing import Protocol

log = logging.getLogger("haqdaar_common.state")


class Cache(Protocol):
    async def get(self, key: str) -> str | None: ...
    async def set(self, key: str, value: str, ttl: int) -> None: ...
    async def clear(self) -> int: ...


class RateLimiter(Protocol):
    async def hit(self, key: str, limit: int, window: int = 60) -> tuple[bool, int]:
        """Count one request for `key`. Returns (allowed, retry_after_seconds)."""
        ...


# ----------------------------------------------------------------------------- in-memory (single process)
class MemoryCache:
    def __init__(self, maxsize: int = 1000) -> None:
        self.maxsize = maxsize
        self._d: OrderedDict[str, tuple[float, str]] = OrderedDict()

    async def get(self, key: str) -> str | None:
        item = self._d.get(key)
        if not item:
            return None
        expires, val = item
        if time.monotonic() > expires:
            self._d.pop(key, None)
            return None
        self._d.move_to_end(key)
        return val

    async def set(self, key: str, value: str, ttl: int) -> None:
        if ttl <= 0:
            return
        self._d[key] = (time.monotonic() + ttl, value)
        self._d.move_to_end(key)
        while len(self._d) > self.maxsize:
            self._d.popitem(last=False)

    async def clear(self) -> int:
        n = len(self._d)
        self._d.clear()
        return n


class MemoryRateLimiter:
    """Sliding window per key; forgets idle keys so memory stays bounded."""

    PRUNE_EVERY = 256

    def __init__(self, clock=time.monotonic) -> None:
        self.hits: dict[str, list[float]] = {}
        self._calls = 0
        self._clock = clock

    def prune(self, now: float, window: int = 60) -> None:
        for k in [k for k, w in self.hits.items() if not w or now - w[-1] >= window]:
            del self.hits[k]

    async def hit(self, key: str, limit: int, window: int = 60) -> tuple[bool, int]:
        now = self._clock()
        self._calls += 1
        if self._calls % self.PRUNE_EVERY == 0:
            self.prune(now, window)
        w = [t for t in self.hits.get(key, []) if now - t < window]
        if len(w) >= limit:
            self.hits[key] = w
            return False, max(1, int(window - (now - w[0])))
        w.append(now)
        self.hits[key] = w
        return True, 0


# ----------------------------------------------------------------------------- Redis (shared by all replicas)
class RedisCache:
    """Values live under a namespace version, so clear() is O(1): bump the version, old keys expire on their own."""

    def __init__(self, redis, prefix: str) -> None:
        self.r, self.prefix = redis, prefix

    async def _ns(self) -> str:
        ver = await self.r.get(f"{self.prefix}:ver")
        return f"{self.prefix}:{(ver.decode() if isinstance(ver, bytes) else ver) or '0'}"

    async def get(self, key: str) -> str | None:
        try:
            v = await self.r.get(f"{await self._ns()}:{key}")
        except Exception as e:  # noqa: BLE001 - fail open
            log.warning("cache get failed: %s", e.__class__.__name__)
            return None
        return v.decode() if isinstance(v, bytes) else v

    async def set(self, key: str, value: str, ttl: int) -> None:
        if ttl <= 0:
            return
        try:
            await self.r.set(f"{await self._ns()}:{key}", value, ex=ttl)
        except Exception as e:  # noqa: BLE001
            log.warning("cache set failed: %s", e.__class__.__name__)

    async def clear(self) -> int:
        await self.r.incr(f"{self.prefix}:ver")
        return -1  # number of entries is unknown (they expire via TTL)


class RedisRateLimiter:
    """Fixed window counter per key (INCR + EXPIRE in one round trip). Shared across every replica."""

    def __init__(self, redis, prefix: str, clock=time.time) -> None:
        self.r, self.prefix, self._clock = redis, prefix, clock

    async def hit(self, key: str, limit: int, window: int = 60) -> tuple[bool, int]:
        now = self._clock()
        bucket = int(now // window)
        k = f"{self.prefix}:{key}:{bucket}"
        try:
            pipe = self.r.pipeline()
            pipe.incr(k)
            pipe.expire(k, window * 2)
            count, _ = await pipe.execute()
        except Exception as e:  # noqa: BLE001 - fail open: never take the API down because Redis is
            log.warning("rate limiter unavailable, allowing request: %s", e.__class__.__name__)
            return True, 0
        if int(count) > limit:
            return False, max(1, int((bucket + 1) * window - now))
        return True, 0


def make_redis(url: str):
    """Return an asyncio Redis client for `url`, or None when no URL is configured (use in-memory state)."""
    if not url:
        return None
    import redis.asyncio as redis

    return redis.from_url(url, socket_timeout=0.5, socket_connect_timeout=0.5, health_check_interval=30)


def make_cache(redis_client, prefix: str, maxsize: int = 1000) -> Cache:
    return RedisCache(redis_client, prefix) if redis_client is not None else MemoryCache(maxsize)


def make_rate_limiter(redis_client, prefix: str) -> RateLimiter:
    return RedisRateLimiter(redis_client, prefix) if redis_client is not None else MemoryRateLimiter()
