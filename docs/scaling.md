# Scaling

## What scales how
| Layer | How it scales | Limits / notes |
|---|---|---|
| recommendation-service, auth-service, eligibility, retrieval, embedding | Horizontally (HPA on CPU). Stateless: cache, rate limits and sessions are in Redis/Postgres | Verified: 3 replicas served 4/4/4 of 12 requests with **one** LLM call total (shared cache) |
| LLM (llm-gateway + model servers) | Add model servers (GPUs) and list them behind the alias; one gateway per GPU with `LLMGW_CONCURRENCY=1` | **The bottleneck.** CPU-based HPA does not help here |
| Qdrant | Single node handles millions of chunks; for HA/scale use distributed mode or Qdrant Cloud | Today: ~5k chunks |
| Postgres | Managed instance; add a connection pooler (PgBouncer) above ~20 auth pods (each pod: pool 10 + overflow 20) | Only auth-service uses it; small writes |
| Redis | One instance is plenty for cache + counters; managed Redis for HA | Losing it loses only cache/counters, never user data |

## Capacity model for the LLM
Each recommendation that misses the cache makes one LLM call. With a ~3B model on one consumer GPU, expect
roughly 3-10 s per call at concurrency 1, i.e. **~6-20 uncached recommendations per minute per GPU**.

What keeps that manageable as users grow:
1. **Shared cache** (Redis, 2 min TTL by default): identical profiles from any replica reuse one answer. Profiles
   cluster heavily (state x occupation x income band), so hit rates rise with traffic.
2. **Request coalescing**: identical concurrent requests in one pod share a single pipeline run.
3. **Load shedding**: when the gateway queue is full it returns 429 and the API answers **rules-only** instead of
   timing out (`reco_fallback_reason_llm_429_total`).
4. **Per-account / per-IP rate limits** stop a single client from consuming the LLM.

Scale-out triggers to watch (all exported as metrics, alerts in `components/monitoring`):
- `AdhikarLlmQueueRejections` / rising `reco_fallback_total` -> add model servers.
- `AdhikarRecommendationLatencyHigh` (p95 > 20 s) -> LLM saturated or cache hit rate dropped.
- HPA at `maxReplicas` -> raise the bound or the pod CPU requests.

## Rules of thumb
- Keep `WEB_CONCURRENCY` at 1-2 per pod and scale pods, not workers: HPA, PDBs and rolling updates work per pod.
- Raise HPA `maxReplicas` before a launch; scale-up is fast (100%/30 s), scale-down is slow (25%/min after 5 min).
- Anonymous limit (`RECO_RATE_LIMIT_PER_MINUTE`) protects the LLM; signed-in users get `RECO_RATE_LIMIT_PER_MINUTE_USER`.
- Behind the ingress, `*_TRUST_FORWARDED_FOR=true` is required so limits are per user, not per ingress pod.
- Use the eval harness (`backend/eval`) after any model/prompt change; latency p50/p95 is part of its report.
