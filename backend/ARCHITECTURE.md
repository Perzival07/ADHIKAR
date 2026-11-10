# Architecture

> System-level docs (auth, scaling, Kubernetes) live in [../docs/architecture.md](../docs/architecture.md).
> This file describes the RAG pipeline services.

Six independent services plus Qdrant. They communicate only over HTTP using the contracts in `contracts/`.
No service imports another service's code. `libs/haqdaar_common` holds logging, request-id and
profile-redaction helpers only.

| Service | Port | Responsibility | Calls |
|---|---|---|---|
| recommendation-service | 8000 (public) | Orchestrates the RAG pipeline; the only API the Flutter app calls | eligibility, retrieval, llm-gateway |
| llm-gateway | 8001 | Provider-neutral text generation behind model aliases | local LLM server (later) |
| embedding-service | 8002 | Provider-neutral embeddings | local embedding model (later) |
| ingestion-service | 8003 | Documents folder -> chunks -> vectors | embedding-service, Qdrant |
| retrieval-service | 8004 | Filtered hybrid search | embedding-service, Qdrant |
| eligibility-service | 8005 | Deterministic eligibility rules | (reads scheme metadata from the docs folder) |
| Qdrant | 6333 | Vector database | |

## Request flow
```
Flutter app
  -> recommendation-service  POST /v1/recommendations {profile, language}
       -> eligibility-service   which schemes can this profile get?
       -> retrieval-service     best chunks among eligible schemes
            -> embedding-service   embed the query
            -> qdrant              filtered vector search
       -> llm-gateway           rank + explain with citations (JSON)
       <- validate output; fall back to rules-only ranking if the LLM fails
  <- ranked schemes + reasons + citations
```

## Ingestion flow
```
data/scheme_docs/* -> ingestion-service -> parse -> chunk
  -> embedding-service -> qdrant upsert (with metadata)
```

## Why this split
- Each service can be built, tested, deployed and scaled alone.
- Only `llm-gateway` and `embedding-service` know vendors/models. Everything else uses model *aliases*,
  so swapping a local model for another (or a cloud one) is a config change in those two services.
- Deterministic eligibility decides who qualifies; the LLM only ranks and explains, and its output is
  validated, so a small model (<=3B) is enough and failures degrade to rules-only results.

## Public API (recommendation-service)
| Endpoint | Purpose |
|---|---|
| `POST /v1/recommendations` | Ranked schemes with reasons, citations, `missing_info`, and a `more` list; `mode` is `rag` or `rules_only` (+ `fallback_reason`) |
| `POST /v1/recommendations/stream` | Same, as SSE progress events: `eligibility`, `retrieval`, `llm_token`*, `result` / `error` |
| `POST /v1/explain` | One scheme in depth (what, documents required, how to apply) for the detail screen |
| `GET /metrics` | Prometheus metrics (optional bearer token via `RECO_METRICS_TOKEN`) |

`Cache-Control: no-cache` bypasses the response cache (used by the eval harness).

## Reliability and safety
- **Graceful degradation:** retrieval or LLM failure (or an open circuit) returns rules-only results instead of an error;
  only an eligibility outage is a 503.
- **Circuit breakers** per downstream service: open after 5 consecutive failures (connection errors, timeouts, 5xx;
  429 "busy" does not count), fail fast for 30 s, then one trial call.
- **Output validation** is the real guarantee: unknown or ineligible scheme ids, unknown / cross-scheme citations and
  duplicates are dropped; eligible always ranks before "unknown".
- **Privacy:** the profile schema forbids unknown fields; logs/metrics contain only `profile_hash` and the state.
  `tests_static/` enforces this with an AST check over every log call.
- **Exposure:** only recommendation-service publishes a port; everything else is on the internal compose network.

## Observability
Every service exposes `GET /metrics` (Prometheus text) and writes one structured JSON access-log line per request with
the propagated `X-Request-ID`, so a single id can be followed across all five services (verified in `tests_e2e`).
Pipeline counters (`reco_*`): requests, fallbacks by reason, hallucinated schemes dropped, invalid citations dropped,
LLM items/citations seen, circuit opens, stage latency histograms; `llmgw_*`: requests, tokens, repairs, queue rejections.

## Testing
`make test` (unit + contract + eval + static policies), `make e2e` (real containers), `python -m eval run` (quality).
