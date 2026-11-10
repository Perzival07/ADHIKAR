# Contributing

## Setup
- Flutter (stable) for the app; Python 3.11 + [uv](https://docs.astral.sh/uv/) + Docker for the backend.
- `cd backend && make install` creates `.venv` with every service in editable mode, pinned by `constraints.txt`.

## Everyday commands
| | |
|---|---|
| `flutter analyze && flutter test` | app checks |
| `make -C backend lint test` | backend lint + all unit/contract/eval/policy tests |
| `make -C backend test-<service>` | one service, e.g. `test-auth-service` |
| `make -C backend e2e` | docker compose stack + end-to-end tests |
| `make -C backend eval` | golden-set quality report against the local stack |
| `make -C backend help` | everything else |

## Rules of the codebase
- **Services never import each other.** Cross-service data goes through `backend/contracts/`. After changing
  `contracts/contract_models.py`: `python contracts/generate.py && python contracts/sync.py`. After changing the auth
  API: `UPDATE_CONTRACTS=1 pytest services/auth-service/tests/test_contract.py` and review the diff.
- **`libs/adhikar_common` is infrastructure only** (logging, ids, metrics, breakers, shared state, JWT verification).
- **Never log profile answers or tokens.** A static test inspects every log call.
- **Eligibility rules change in two places**: the Dart engine and `eligibility-service/.../rules/*.yaml`. Regenerate
  the parity fixture (`tests/fixtures/make_parity_profiles.py` + `dart run tool/dump_engine_parity.dart ...`).
- **Database changes** are Alembic migrations in `services/auth-service/src/auth_service/migrations/versions/` and must
  be backward compatible for one release.
- **Dependencies**: add to the service's `pyproject.toml`, install, then `make lock` and `make audit`.
- **Kubernetes**: edit YAML in `deploy/k8s`; CI renders both overlays and validates them strictly.

## Pull requests
CI must be green. Prompt/model changes include an eval comparison (`python -m eval compare old.json new.json`).
