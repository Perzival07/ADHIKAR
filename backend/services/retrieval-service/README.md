# retrieval-service

Filtered hybrid (semantic + keyword) search.

- Port: 8004
- Env prefix: `RETRIEVAL_`
- Run: `uvicorn retrieval_service.main:app --port 8004`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).
