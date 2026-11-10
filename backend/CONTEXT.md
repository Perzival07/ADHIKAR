# ADHIKAR backend: global context

(Extracted from ../plan.txt. Read this before changing any service.)

Project: ADHIKAR is a Flutter app (repo root) that helps Indian citizens find
welfare schemes and internships. It has 1,184 schemes in
lib/data/schemes_corpus.dart, a rule-based matcher in
lib/core/services/scheme_engine.dart, and a citizen profile model in
lib/core/models/citizen_profile.dart. The app supports 23 languages.

Goal: add a RAG (retrieval-augmented generation) system. Documents about
schemes live in a folder. Given a user's profile, the system retrieves the
relevant documents and an LLM suggests the schemes that fit the user, explains
why, and cites its sources.

Architecture rules (apply to every prompt):
1. NOT A MONOLITH. Backend = separate services under backend/services/. Each
   service has its own pyproject.toml, Dockerfile, tests, config and README.
   Services can be built, run, tested and deployed independently. They talk
   only over HTTP using the contracts in backend/contracts/. No service imports
   another service's code. A tiny shared library is allowed for logging and
   request-id helpers only, never for business logic.
2. LLM INDEPENDENCE. Only the llm-gateway service knows which LLM is used.
   Every other service calls the gateway's provider-neutral API with a model
   ALIAS (e.g. "recommender"), never a vendor model name. Switching from a
   local model to a cloud model must be a config change in llm-gateway only.
   The same rule applies to embeddings and embedding-service.
3. LOCAL-FIRST. The first real provider is a locally hosted model (Ollama or
   any OpenAI-compatible local server such as llama.cpp server, LM Studio or
   vLLM). DO NOT download any model, run "ollama pull", or fetch Hugging Face
   weights on this machine. Code must start and pass all tests using the
   "mock" LLM provider and the "hash" embedding provider. Model downloads are
   documented for the user's PC only (P13).
4. Stack: Python 3.11+, FastAPI, Pydantic v2, httpx, pytest. Vector database:
   Qdrant (its own container). Package manager: uv (fall back to pip if uv is
   unavailable).
5. No secrets in the repo. Config comes from environment variables, with a
   .env.example per service. Never add .env files to Flutter assets (that
   leaked a key before).
6. Every service exposes GET /health (process up) and GET /ready (dependencies
   reachable), logs JSON with a propagated X-Request-ID header, and sets
   timeouts on every outbound call.
7. Privacy: the profile includes caste category, income, disability and
   marital status. Never log raw profiles. Log a hash or redacted fields only.
8. Deterministic eligibility decides who qualifies. The LLM only RANKS and
   EXPLAINS schemes from the eligible, retrieved set. It must never introduce
   a scheme that is not in its context. This is what makes a small (≤3B)
   model workable.
9. SMALL-MODEL DESIGN. Assume the production LLM is a ~1.5–3B instruct model
   (max ~4B) at 4–5-bit quantization with a 4k–8k context window:
   - keep prompts short
   - keep the retrieved-context token budget configurable (default ~3k)
   - process one request at a time per GPU
   - always keep the rules-only fallback
   Never design anything that requires a bigger model.
10. KNOWLEDGE LIVES IN RAG, NOT IN THE WEIGHTS. Scheme facts (amounts,
    deadlines, eligibility) always come from retrieved documents. Optional
    fine-tuning (P16–P17) teaches the model the TASK: valid JSON, citing
    chunk ids, only using given documents, simple Hindi/regional
    explanations. It never teaches scheme facts.

Target deployment hardware (the user's PC; used in P13/P16/P17):
- GPU 0: RTX 3070 Ti, 8 GB VRAM. Dedicated to LLM inference.
- GPU 1: GTX 1650 Super, 4 GB VRAM. Drives the display only; no inference.
- 32 GB RAM, Intel i5-10500 (6C/12T). The embedding model runs on the CPU.
- Hard requirement: the graphics driver must stay stable while the LLM runs
  in the background. That means a VRAM headroom of ≥3 GB, a single model
  loaded, concurrency 1, a capped context, an optional GPU power limit, and
  never training and serving on the same GPU at the same time.

Target layout:
  backend/
    CONTEXT.md                 (this block)
    ARCHITECTURE.md
    docker-compose.yml
    Makefile
    contracts/                 (OpenAPI specs + JSON Schemas, source of truth)
    libs/adhikar_common/       (logging + request-id ONLY)
    data/scheme_docs/          (THE DOCUMENTS FOLDER)
    services/
      llm-gateway/             :8001  provider-neutral text generation
      embedding-service/       :8002  provider-neutral embeddings
      ingestion-service/       :8003  documents folder -> chunks -> vectors
      retrieval-service/       :8004  filtered semantic + keyword search
      eligibility-service/     :8005  deterministic rule checks
      recommendation-service/  :8000  orchestrator, the only public API
    eval/                      (offline quality evaluation)
  qdrant                       :6333  (container)

Request flow:
  Flutter app
    -> recommendation-service  POST /v1/recommendations {profile, language}
         -> eligibility-service   which schemes can this profile get?
         -> retrieval-service     find the best chunks among eligible schemes
              -> embedding-service   embed the query
              -> qdrant              filtered vector search
         -> llm-gateway           rank + explain with citations (JSON)
         <- validate output, fall back to rule-only ranking if the LLM fails
    <- ranked schemes + reasons + citations

Ingestion flow (offline / on change):
  data/scheme_docs/* -> ingestion-service -> parse -> chunk
    -> embedding-service -> qdrant upsert (with metadata)
