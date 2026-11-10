# eligibility-service

Deterministic eligibility rules.

- Port: 8005
- Env prefix: `ELIG_`
- Run: `uvicorn eligibility_service.main:app --port 8005`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).
