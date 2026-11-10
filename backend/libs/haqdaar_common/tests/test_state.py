import fakeredis.aioredis
import pytest
from haqdaar_common import (
    MemoryCache,
    MemoryRateLimiter,
    RedisCache,
    RedisRateLimiter,
    make_cache,
    make_rate_limiter,
)


@pytest.fixture
def redis():
    return fakeredis.aioredis.FakeRedis()


@pytest.mark.parametrize("kind", ["memory", "redis"])
async def test_cache_roundtrip_ttl_and_clear(kind, redis):
    c = MemoryCache() if kind == "memory" else RedisCache(redis, "t")
    assert await c.get("k") is None
    await c.set("k", "v", 60)
    assert await c.get("k") == "v"
    await c.set("zero", "v", 0)  # ttl 0 = do not cache
    assert await c.get("zero") is None
    await c.clear()
    assert await c.get("k") is None
    await c.set("k", "v2", 60)
    assert await c.get("k") == "v2"


async def test_redis_cache_is_shared_between_replicas(redis):
    a, b = RedisCache(redis, "reco"), RedisCache(redis, "reco")
    await a.set("x", "1", 60)
    assert await b.get("x") == "1"
    await b.clear()  # clearing on one replica invalidates for all
    assert await a.get("x") is None


async def test_memory_cache_evicts_lru():
    c = MemoryCache(maxsize=2)
    for k in "abc":
        await c.set(k, k, 60)
    assert await c.get("a") is None and await c.get("c") == "c"


@pytest.mark.parametrize("kind", ["memory", "redis"])
async def test_rate_limiter_blocks_over_limit_per_key(kind, redis):
    t = [1000.0]
    rl = MemoryRateLimiter(clock=lambda: t[0]) if kind == "memory" else RedisRateLimiter(redis, "rl", clock=lambda: t[0])
    results = [await rl.hit("ip1", 3) for _ in range(4)]
    assert [ok for ok, _ in results] == [True, True, True, False] and results[-1][1] >= 1
    assert (await rl.hit("ip2", 3))[0] is True  # other keys unaffected
    t[0] += 61
    assert (await rl.hit("ip1", 3))[0] is True  # next window


async def test_redis_rate_limit_is_shared_between_replicas(redis):
    a, b = RedisRateLimiter(redis, "rl", clock=lambda: 50.0), RedisRateLimiter(redis, "rl", clock=lambda: 50.0)
    assert (await a.hit("u", 2))[0] and (await b.hit("u", 2))[0]
    assert (await a.hit("u", 2))[0] is False  # the third request is blocked whichever replica gets it


class BrokenRedis:
    def __getattr__(self, name):
        raise ConnectionError("redis down")


async def test_redis_failures_fail_open():
    assert await RedisCache(BrokenRedis(), "c").get("k") is None
    await RedisCache(BrokenRedis(), "c").set("k", "v", 10)  # no exception
    assert await RedisRateLimiter(BrokenRedis(), "rl").hit("k", 1) == (True, 0)


def test_factories_choose_backend(redis):
    assert isinstance(make_cache(None, "p"), MemoryCache) and isinstance(make_cache(redis, "p"), RedisCache)
    assert isinstance(make_rate_limiter(None, "p"), MemoryRateLimiter) and isinstance(make_rate_limiter(redis, "p"), RedisRateLimiter)


def test_memory_limiter_prunes_idle_keys():
    rl = MemoryRateLimiter()
    rl.hits = {f"k{i}": [0.0] for i in range(500)} | {"live": [100.0]}
    rl.prune(now=110.0)
    assert set(rl.hits) == {"live"}
