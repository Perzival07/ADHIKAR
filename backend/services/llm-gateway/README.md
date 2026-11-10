# llm-gateway

Provider-neutral text generation. The only service that knows which LLM is used.

- Port: 8001
- Env prefix: `LLMGW_`
- Run: `uvicorn llm_gateway.main:app --port 8001`
- Test: `pytest`

Talks to other services only over HTTP (see `../../contracts/`).
