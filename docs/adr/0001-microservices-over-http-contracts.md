# ADR 0001: Independent services with HTTP contracts
**Status:** accepted
**Context:** the RAG system mixes very different workloads (rules, vector search, embeddings, GPU-bound LLM, accounts).
**Decision:** one service per concern, communicating only over versioned HTTP contracts (`backend/contracts`, `/v1`).
A tiny shared library is allowed for infrastructure only.
**Consequences:** each part scales and deploys independently (the LLM can sit on GPU nodes); more moving parts,
mitigated by one Dockerfile, one compose file, Kustomize and request-id tracing.
