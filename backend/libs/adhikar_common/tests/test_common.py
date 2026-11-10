import json
import logging

from adhikar_common import (
    RequestIDMiddleware,
    get_request_id,
    outbound_headers,
    profile_hash,
    redact_profile,
    setup_json_logging,
)
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route
from starlette.testclient import TestClient


def _app():
    async def h(request):
        return PlainTextResponse(get_request_id())

    return Starlette(routes=[Route("/", h)], middleware=[])


def test_request_id_generated_and_echoed():
    app = RequestIDMiddleware(_app())
    c = TestClient(app)
    r = c.get("/")
    assert r.headers["x-request-id"] == r.text
    assert len(r.text) >= 16


def test_request_id_propagated():
    c = TestClient(RequestIDMiddleware(_app()))
    r = c.get("/", headers={"X-Request-ID": "abc-123"})
    assert r.text == "abc-123"
    assert r.headers["x-request-id"] == "abc-123"


def test_outbound_headers_default():
    assert outbound_headers()["X-Request-ID"] == "-"


def test_redaction_has_no_sensitive_fields():
    p = {"state": "Assam", "age": 30, "socialCategory": "SC", "annualIncomeRange": "< 1 Lakh"}
    r = redact_profile(p)
    assert set(r) == {"profile_hash", "state"}
    assert profile_hash(p) == profile_hash(dict(reversed(list(p.items()))))


def test_json_logging(capsys):
    setup_json_logging("svc")
    logging.getLogger("x").info("hello")
    line = capsys.readouterr().out.strip().splitlines()[-1]
    data = json.loads(line)
    assert data["service"] == "svc" and data["msg"] == "hello"
