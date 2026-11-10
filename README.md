# Haqdaar

Helps Indian citizens find the government welfare schemes and internships they are entitled to, in 23 languages.

- **Mobile/web app (Flutter)**: works fully offline with on-device eligibility rules (313 schemes).
- **Backend (optional, Kubernetes)**: real accounts plus AI-ranked recommendations with sources (RAG), built to
  scale horizontally as users are onboarded.

```
app (Flutter) ──► ingress ──► recommendation-service ──► eligibility · retrieval (Qdrant) · llm-gateway
                         └──► auth-service (Postgres)        cache + rate limits shared in Redis
```

| Doc | What's in it |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Services, request lifecycle, design decisions ([ADRs](docs/adr/)) |
| [docs/deployment.md](docs/deployment.md) | Kubernetes prerequisites, secrets, first deploy, upgrades, rollback |
| [docs/scaling.md](docs/scaling.md) | What scales how, LLM capacity model, scale-out triggers |
| [docs/security.md](docs/security.md) | Accounts/tokens, platform hardening, data handling |
| [docs/runbook.md](docs/runbook.md) | Alerts and what to do about them |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow and quality gates |
| [plan.txt](plan.txt) | Build plan; real local-LLM setup and fine-tuning steps (P13, P16, P17) |

## Repository layout

```
lib/, test/, android/, ios/, web/ ...   Flutter app (standard Flutter layout at the root)
tool/                                   Dart tools: corpus export, rules parity dump
backend/
  services/<name>/                      7 independent FastAPI services (own tests, config, README)
  libs/haqdaar_common/                  infrastructure-only shared library
  contracts/                            OpenAPI + JSON Schemas (source of truth for every API)
  data/scheme_docs/                     knowledge base (markdown/PDF/DOCX/HTML per scheme)
  docker/                               one service Dockerfile + the scheme-docs data image
  eval/                                 golden-set evaluation harness
  tests_static/, tests_e2e/             policy checks, end-to-end tests
deploy/k8s/                             Kustomize base + dev/prod overlays + monitoring component
docs/                                   architecture, deployment, scaling, security, runbook, ADRs
.github/workflows/                      CI (every PR) and release (tags)
```

## Quick start

**App only (offline):**
```sh
flutter pub get && flutter run -d chrome
```
Demo logins: `citizen@haqdaar.gov.in` or `9876543210`, password `password123`.

**Full local stack (mock LLM, no models needed):**
```sh
cd backend
make install          # python venv with every service (needs uv)
make test             # unit + contract + eval + policy tests
make up               # docker compose: all services + Postgres + Redis + Qdrant
make ingest           # load the scheme documents
cd .. && flutter run -d chrome \
  --dart-define=RAG_API_URL=http://localhost:8000 \
  --dart-define=AUTH_API_URL=http://localhost:8006
```
With `AUTH_API_URL` the app uses real accounts: sign-up codes are sent by auth-service (in local development they
are printed in its log: `docker compose logs auth-service | grep OTP`). Without it, the offline demo accounts are used.
Android emulator: use `http://10.0.2.2:<port>` instead of `localhost`.

**Kubernetes:** see [docs/deployment.md](docs/deployment.md) (`make images`, `make k8s-dev-secrets`,
`kubectl apply -k deploy/k8s/overlays/dev`).

## Quality gates
Every pull request runs (see [.github/workflows/ci.yml](.github/workflows/ci.yml)):
backend lint + ~900 tests (incl. a real-Postgres migration test), contract freshness, dependency audit,
Flutter analyze + tests, Kubernetes manifest rendering + strict schema validation, and a docker-compose end-to-end
run with a golden-set quality gate. Releases add image scanning, SBOMs and signed provenance.

## Use a real local LLM
The stack runs on a mock LLM and a hash embedder until you configure models. Point the `recommender` alias in
`backend/services/llm-gateway/models.yaml` (and `deploy/k8s/base/models.yaml`) at your model server and set the
`EMBED_*` variables of embedding-service, then re-ingest. PC-side setup and fine-tuning: plan.txt P13, P16, P17.

## Known limitations
- **Mock models only** until P13: recommendation quality numbers on the mock stack say nothing about a real model.
- **Corpus vs. rules (pre-existing):** ~10 scheme ids in the original Dart rules (e.g. `pm_suraksha_bima`, `mgnrega`)
  are not in the 313-scheme corpus, so those specific rules never fire.
- **SMS OTP is not implemented**; codes are sent by email. Phone-number accounts can sign in with a password.
- **The LLM is the scaling bottleneck**: each uncached recommendation needs one model call. Caching, coalescing,
  rate limits and rules-only fallback keep the API responsive; throughput grows with model servers
  ([docs/scaling.md](docs/scaling.md)).
- **No git history yet**: initialise a repository before relying on the CI/CD workflows.

## Android release signing
Create `android/key.properties` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, then
`flutter build apk --release`. Without that file the build is signed with the debug key and must not be published.
