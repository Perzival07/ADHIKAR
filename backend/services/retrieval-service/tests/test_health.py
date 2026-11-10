from fastapi.testclient import TestClient

from retrieval_service.config import Settings
from retrieval_service.main import create_app


def _client():
    return TestClient(create_app(Settings(qdrant_url="http://127.0.0.1:1", embedding_url="http://127.0.0.1:1")))


def test_health_ok_even_when_dependencies_down():
    assert _client().get("/health").json()["status"] == "ok"


def test_ready_reports_dependency_state():
    r = _client().get("/ready")
    assert r.status_code == 503 and r.json()["checks"] == {"qdrant": False, "embedding-service": False}


def test_request_id_header_echoed():
    assert _client().get("/health", headers={"X-Request-ID": "t-1"}).headers["x-request-id"] == "t-1"
