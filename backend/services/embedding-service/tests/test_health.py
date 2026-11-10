from fastapi.testclient import TestClient

from embedding_service.main import create_app


def test_health_and_ready():
    c = TestClient(create_app())
    r = c.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"
    assert c.get("/ready").status_code == 200


def test_request_id_header_echoed():
    c = TestClient(create_app())
    assert c.get("/health", headers={"X-Request-ID": "t-1"}).headers["x-request-id"] == "t-1"
