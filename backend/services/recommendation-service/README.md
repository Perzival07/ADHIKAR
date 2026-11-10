# recommendation-service

RAG orchestrator and the only public API.

- Port: 8000
- Env prefix: `RECO_`
- Run: `uvicorn recommendation_service.main:app --port 8000`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).
