# Changelog

## 2026-11-10 (later): production restructure for Kubernetes and user growth

### Added
- **auth-service** (Postgres): sign-up/sign-in with server-sent email OTP, argon2id passwords with lockout, ES256 access
  tokens + rotating refresh tokens with reuse detection, profile updates, account deletion, JWKS endpoint, Alembic
  migrations under a Postgres advisory lock, production config guardrails, dev-only demo users.
- **Horizontal scaling**: response cache and rate limits shared in Redis (fail open), request coalescing,
  per-account vs per-IP limits, JWT verification in the recommendation API (`RECO_AUTH_MODE` off/optional/required).
- **Kubernetes** (`deploy/k8s`): Kustomize base + dev/prod overlays, HPAs, PDBs, NetworkPolicies, Pod Security
  "restricted", ingress, nightly ingest CronJob, scheme-docs data image, Prometheus monitoring + alerts.
  Verified on a live k3s cluster: ingestion, auth + RAG through JWKS, network policies, 3-replica load balancing with a
  shared cache, and a rolling update with zero failed requests.
- **Hardened image**: one multi-stage, non-root Dockerfile for all services; app factories; graceful shutdown.
- **CI/CD**: GitHub Actions for PRs (tests, Postgres migration test, audit, Flutter, manifest validation, e2e + quality
  gate) and releases (images, Trivy, SBOM, provenance, pinned prod manifests).
- **App**: real accounts when built with `AUTH_API_URL` (refresh token in Keychain/Keystore, access token sent to the
  recommendation API), server-sent OTP, 8-character password minimum, "Delete my account".
- Docs: architecture, deployment, scaling, security, runbook, ADRs, contributing guide.

### Fixed
- Alembic migrations could be silently rolled back on Postgres (found when deploying to Kubernetes; regression test
  added against a real Postgres).
- Images listened on the wrong port when built without the per-service build argument.
- Kustomize overlays generated secrets outside the namespace, leaving references unresolved.

## 2026-11-10: RAG recommendation backend and Flutter integration

### Added
- **Backend** (`backend/`): six independent FastAPI services + Qdrant, defined by OpenAPI/JSON-Schema contracts
  generated from one Pydantic source (`backend/contracts/`).
  - `llm-gateway`: provider-neutral LLM behind model aliases; mock, Ollama and OpenAI-compatible adapters; JSON
    validate-and-repair; concurrency limit (default 1) with bounded queue; SSE streaming.
  - `embedding-service`: hash (offline), sentence-transformers (local folder, CPU default) and Ollama providers.
  - `ingestion-service`: folder -> chunks -> vectors for md/txt/pdf/docx/html, idempotent, manifest-based deletes,
    prompt-injection flagging, watch mode.
  - `retrieval-service`: filtered semantic + BM25 search with rank fusion, per-scheme cap, language fallback,
    optional LLM reranker (off by default).
  - `eligibility-service`: the Flutter `SchemeEngine` ported to declarative YAML rules, parity-tested against the
    Dart engine on 431 profiles (identical eligible set, scores and reason text).
  - `recommendation-service`: the orchestrator and only public API (`/v1/recommendations`, `/v1/explain`, SSE
    stream); output validation drops unknown schemes/citations; rules-only fallback; cache, rate limit, body limit.
- Compact small-model prompts (v2), explain prompt, translate-via-pivot for low-resource languages.
- Evaluation harness (`backend/eval`) with 46 golden profiles, run/compare CLI and a recorded baseline.
- Observability and resilience: Prometheus `/metrics` on every service, request-id tracing through all services,
  circuit breakers on inter-service calls, pinned dependencies (`constraints.txt`), `pip-audit`, static policy tests.
- ~800 backend tests plus a docker-compose end-to-end suite (`make e2e`).
- **Flutter**: optional AI recommendations (`RAG_API_URL`), instant rule-based results that upgrade to AI results,
  "AI-assisted" / "Rule-based" badge, source chips, missing-info prompts, Settings toggle, repository with offline
  fallback; 16 new tests. `tool/export_scheme_docs.dart` and `tool/dump_engine_parity.dart`.

### Fixed
- Review follow-ups: per-client rate limiting behind proxies (and no unbounded memory), cache invalidation endpoint,
  serialized ingestion runs, results screen refreshes AI text on language/AI-setting change, and the Delhi student
  scheme now matches `Delhi (NCT)` (fixed in the Dart engine and the Python rules, parity re-verified).
- Splash screen overflow in short windows; "Latest" tab emptying out as the calendar advanced; `setState`
  after-dispose crashes in the auth screens.

### Security
- Removed a hard-coded Gmail app password and stopped bundling `.env` (Gemini key) as an app asset; both must be
  rotated/revoked by the owner. Demo account passwords are now stored as salted hashes.
- Request profiles forbid unknown fields, so name/phone/email can never reach the backend; logs and metrics carry
  only a profile hash.

### Not done yet
- Real local LLM / embedding model setup, soak test and optional fine-tuning (plan.txt P13, P16, P17).
