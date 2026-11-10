# embedding-service

Provider-neutral embeddings. The only service that knows which embedding model is used.

- Port: 8002
- Env prefix: `EMBED_`
- Run: `uvicorn embedding_service.main:app --port 8002`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).

## Providers (`EMBED_PROVIDER`)
- `hash` (default): deterministic offline fake for dev/tests.
- `sentence_transformers`: loads a LOCAL model folder (`EMBED_MODEL_PATH`), `EMBED_DEVICE=cpu` by default so the
  GPU stays free for the LLM. Never auto-downloads (`HF_HUB_OFFLINE=1`). Install extra: `pip install sentence-transformers`.
- `ollama`: `EMBED_OLLAMA_MODEL` on the local Ollama server.

### Multilingual note
Documents and queries can be Hindi or other Indian languages, so on the PC pick a **multilingual** embedding
model (e.g. `BAAI/bge-m3`, or a `multilingual-e5-base` class model). For e5-style models set
`EMBED_QUERY_PREFIX="query: "` and `EMBED_DOCUMENT_PREFIX="passage: "`.

### Collections never mix
`model_id` (model name + dim) is returned on every response. ingestion/retrieval name the Qdrant collection from it,
so changing the embedding model creates a new collection instead of mixing vectors.

Inputs longer than `EMBED_MAX_INPUT_CHARS` are truncated and flagged in `truncated[]`; never silently.
