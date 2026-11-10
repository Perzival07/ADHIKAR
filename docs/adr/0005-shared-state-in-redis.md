# ADR 0005: Shared cache and rate limits in Redis (fail open)
**Status:** accepted
**Decision:** response cache and rate-limit counters live in Redis so any replica can serve any request. If Redis is
unavailable both fail open (no cache, no limits) instead of failing requests.
**Consequences:** horizontal scaling is "add pods"; a Redis outage costs LLM capacity, not availability. Ingress-level
rps limits remain as a backstop.
