"""The service's generated OpenAPI must match contracts/openapi/retrieval-service.yaml."""
from pathlib import Path

import pytest
import yaml

from retrieval_service.main import create_app

SPEC = Path(__file__).resolve().parents[3] / "contracts" / "openapi" / "retrieval-service.yaml"
pytestmark = pytest.mark.skipif(not SPEC.exists(), reason="contracts dir not available (e.g. in docker)")


def _schema_props(components, name):
    s = components[name]
    return set(s.get("properties", {})), set(s.get("required", []))


def test_paths_and_methods_match_contract():
    spec = yaml.safe_load(SPEC.read_text())
    live = create_app().openapi()
    for path, methods in spec["paths"].items():
        assert path in live["paths"], f"missing path {path}"
        for method in methods:
            assert method in live["paths"][path], f"missing {method} {path}"


def test_component_schemas_match_contract():
    spec = yaml.safe_load(SPEC.read_text())["components"]["schemas"]
    live = create_app().openapi()["components"]["schemas"]
    for name in spec:
        if name == "ErrorResponse":
            continue
        assert name in live, f"missing schema {name}"
        assert _schema_props(live, name) == _schema_props(spec, name), name


