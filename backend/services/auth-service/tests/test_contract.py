"""The auth API is consumed by the mobile app: its OpenAPI is snapshotted in contracts/ and reviewed on change.

Regenerate after an intentional API change:  UPDATE_CONTRACTS=1 pytest tests/test_contract.py
"""
import json
import os
from pathlib import Path

import pytest
import yaml

from auth_service.config import Settings
from auth_service.main import create_app

SPEC = Path(__file__).resolve().parents[3] / "contracts" / "openapi" / "auth-service.yaml"


def live_spec() -> dict:
    spec = create_app(Settings(database_url="sqlite+aiosqlite:///:memory:")).openapi()
    return json.loads(json.dumps(spec))  # normalise


def test_openapi_matches_snapshot():
    live = live_spec()
    if os.environ.get("UPDATE_CONTRACTS") or not SPEC.exists():
        SPEC.write_text(yaml.safe_dump(live, sort_keys=False, allow_unicode=True))
        pytest.skip("snapshot written")
    assert yaml.safe_load(SPEC.read_text()) == live, "auth API changed: review, then run with UPDATE_CONTRACTS=1"
