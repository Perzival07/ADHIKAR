# Architecture

Haqdaar is a Flutter app plus a backend of independent services. The app works fully offline (on-device rules);
the backend adds real accounts and AI-ranked, source-cited recommendations.

```
                         Internet
                            |
                 Ingress (TLS, body limit, rps limit)
              /v1/recommendations, /v1/explain | /v1/auth, /v1/users, /.well-known/jwks.json
                    |                                   |
      recommendation-service :8000            auth-service :8006 ---- Postgres (managed)
      (stateless, HPA 3..50)                  (stateless, HPA 3..20)
        |  verifies JWTs via JWKS ------------------^      \
        |  cache + rate limits --------------------------- Redis (shared by all replicas)
        |-- eligibility-service :8005   deterministic rules (docs from the scheme-docs image)
        |-- retrieval-service   :8004 -- embedding-service :8002
        |        |                  \-- Qdrant (vectors)
        '-- llm-gateway :8001  -- local / cloud model servers (aliases in models.yaml)

  CronJob "ingest" (nightly): scheme-docs image -> chunks -> embeddings -> Qdrant, then clears the reco cache
```

## Services

| Service | Responsibility | State | Scales by |
|---|---|---|---|
| recommendation-service | Public RAG API: eligibility -> retrieval -> LLM -> validation; rules-only fallback | none (Redis) | CPU (HPA) |
| auth-service | Accounts, server-side OTP, ES256 JWT + rotating refresh tokens, account deletion | Postgres | CPU (HPA) |
| eligibility-service | Deterministic rules (parity-tested with the app's Dart engine) | read-only docs | CPU (HPA) |
| retrieval-service | Filtered semantic + BM25 search with rank fusion | none (Qdrant) | CPU (HPA) |
| embedding-service | Provider-neutral embeddings (hash / local model / Ollama) | none | CPU (HPA) |
| llm-gateway | Provider-neutral LLM access behind aliases; concurrency limit + queue | none | number of model servers |
| ingest (CronJob) | Folder -> chunks -> vectors; single writer | small PVC (manifest) | n/a |

Services talk only over HTTP using the contracts in `backend/contracts/` (OpenAPI 3.1, generated from one Pydantic
source; the auth API is snapshotted for the mobile client). No service imports another's code; `libs/haqdaar_common`
holds infrastructure only (logging, request ids, metrics, circuit breaker, shared state, JWT verification).

## Key design choices
See the decision records in `docs/adr/`. In short:
- **Deterministic eligibility, LLM only ranks/explains**, and every LLM output is validated (unknown schemes and
  citations dropped). This keeps a small local model safe and makes failures degrade to rules-only answers.
- **LLM independence**: only llm-gateway and embedding-service know vendors/models.
- **Stateless request path**: cache, rate limits and coalescing are shared through Redis, so any replica can serve any
  request and scaling is "add pods".
- **No shared secrets between services**: auth-service signs ES256 tokens; others verify with the published JWKS.

## Request lifecycle (recommendations)
1. Ingress -> recommendation-service. `edge_guard`: verify bearer token (optional/required per `RECO_AUTH_MODE`),
   rate-limit per account or per IP (Redis).
2. Cache lookup (Redis). Concurrent identical requests in a pod are coalesced into one computation.
3. eligibility-service decides who qualifies (authoritative).
4. retrieval-service returns the best chunks among eligible schemes (state + language filters).
5. llm-gateway ranks and explains (JSON schema, repair once). Circuit breakers fail fast when a dependency is down.
6. Output validation, then the answer is cached. Any failure in 4-5 returns rules-only results instead of an error.

Every hop carries `X-Request-ID`; each service writes one JSON access-log line per request and exposes `/metrics`.
