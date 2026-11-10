from fastapi.testclient import TestClient

from ingestion_service.config import Settings
from ingestion_service.main import create_app


def _app():
    # unreachable dependencies: the service must still start; /ready must say so
    return create_app(Settings(qdrant_url="http://127.0.0.1:1", embedding_url="http://127.0.0.1:1", state_dir=":memory:"))


def test_health_ok_even_when_dependencies_down():
    c = TestClient(_app())
    assert c.get("/health").json()["status"] == "ok"


def test_ready_reports_dependency_state():
    c = TestClient(_app())
    r = c.get("/ready")
    assert r.status_code == 503 and r.json()["checks"] == {"qdrant": False, "embedding-service": False}


def test_request_id_header_echoed():
    c = TestClient(_app())
    assert c.get("/health", headers={"X-Request-ID": "t-1"}).headers["x-request-id"] == "t-1"
