# Contracts

Source of truth for every cross-service interface.

- `contract_models.py`: Pydantic models. Edit here only.
- `generate.py`: derives `schemas/*.json` (JSON Schema 2020-12) and `openapi/*.yaml` (OpenAPI 3.1) from the models.
- `sync.py`: copies `contract_models.py` into each service (identical copies; no cross-service imports).

```
python contracts/generate.py && python contracts/sync.py      # after any change
python contracts/generate.py --check && python contracts/sync.py --check   # CI
```

## Versioning
All endpoints live under a path prefix (`/v1`). Additive, backward-compatible changes (new optional fields)
stay in `/v1`. Anything breaking (removed/renamed field, changed meaning, new required field) requires a new
prefix (`/v2`) served alongside `/v1` until clients migrate.

## Privacy
`CitizenProfile` forbids unknown fields (`extra="forbid"`): name, phone and email must never be sent.
