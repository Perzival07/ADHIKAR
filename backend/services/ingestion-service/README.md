# ingestion-service

Documents folder -> chunks -> vectors in Qdrant.

- Port: 8003
- Env prefix: `INGEST_`
- Run: `uvicorn ingestion_service.main:app --port 8003`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).
