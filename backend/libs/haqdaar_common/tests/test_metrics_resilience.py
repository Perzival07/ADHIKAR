from haqdaar_common import (
    CircuitBreaker,
    CircuitOpen,
    MetricsMiddleware,
    Registry,
    metrics_response,
)
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route
from starlette.testclient import TestClient


def test_registry_renders_prometheus_text():
    r = Registry()
    c = r.counter("things_total", "Things", ("kind",))
    c.inc(kind="a")
    c.inc(2, kind="a")
    c.inc(kind='b"x')
    h = r.histogram("lat_seconds", "Latency", ("op",), buckets=(0.1, 1.0))
    h.observe(0.05, op="x")
    h.observe(0.5, op="x")
    h.observe(5, op="x")
    r.gauge("up", "Up").set(1)
    text = r.render()
    assert '# TYPE things_total counter' in text and 'things_total{kind="a"} 3' in text and 'things_total{kind="b\\"x"} 1' in text
    assert 'lat_seconds_bucket{op="x",le="0.1"} 1' in text and 'lat_seconds_bucket{op="x",le="1"} 2' in text
    assert 'lat_seconds_bucket{op="x",le="+Inf"} 3' in text and 'lat_seconds_count{op="x"} 3' in text
    assert "up 1" in text and r.counter("things_total") is c  # same name -> same metric


def _app(registry):
    async def ok(request):
        return PlainTextResponse("ok")

    async def boom(request):
        raise RuntimeError("x")

    async def metrics(request):
        return metrics_response(registry)

    app = Starlette(routes=[Route("/items/{id}", ok), Route("/boom", boom), Route("/metrics", metrics)])
    return MetricsMiddleware(app, registry, "svc")


def test_http_middleware_counts_by_route_template_not_raw_path():
    r = Registry()
    c = TestClient(_app(r), raise_server_exceptions=False)
    c.get("/items/1")
    c.get("/items/2")
    c.get("/nope")
    assert c.get("/boom").status_code == 500
    text = c.get("/metrics").text
    assert 'haqdaar_http_requests_total{service="svc",method="GET",route="unmatched",status="200"} 2' in text or "unmatched" in text
    assert "/items/1" not in text and "/items/2" not in text  # no unbounded label cardinality
    assert 'status="500"' in text and 'status="404"' in text
    assert "haqdaar_http_request_duration_seconds_count" in text
    assert 'route="/metrics"' not in text  # the scrape itself is not counted


def test_circuit_breaker_lifecycle():
    t = [0.0]
    opened = []
    b = CircuitBreaker("dep", failure_threshold=3, reset_timeout=10, clock=lambda: t[0], on_open=opened.append)
    assert b.state == "closed"
    for _ in range(2):
        b.before_call()
        b.record_failure()
    assert b.state == "closed"
    b.before_call()
    b.record_success()  # a success resets the consecutive-failure count
    for _ in range(3):
        b.before_call()
        b.record_failure()
    assert b.state == "open" and opened == ["dep"]
    try:
        b.before_call()
        raise AssertionError("should be open")
    except CircuitOpen:
        pass
    t[0] = 11.0
    assert b.state == "half_open"
    b.before_call()  # one trial allowed
    try:
        b.before_call()
        raise AssertionError("second concurrent trial must be refused")
    except CircuitOpen:
        pass
    b.record_failure()  # trial fails -> open again immediately
    assert b.state == "open" and opened == ["dep"]  # not re-announced
    t[0] = 22.0
    b.before_call()
    b.record_success()
    assert b.state == "closed" and b.failures == 0


def test_access_log_has_request_id_and_no_query_string(capsys):
    import json

    from haqdaar_common import (
        AccessLogMiddleware,
        RequestIDMiddleware,
        setup_json_logging,
    )

    setup_json_logging("svc")

    async def ok(request):
        return PlainTextResponse("ok")

    app = RequestIDMiddleware(AccessLogMiddleware(Starlette(routes=[Route("/v1/x", ok), Route("/health", ok)])))
    c = TestClient(app)
    c.get("/v1/x?secret=1", headers={"X-Request-ID": "trace-42"})
    c.get("/health")
    lines = [json.loads(ln) for ln in capsys.readouterr().out.splitlines() if ln.startswith("{")]
    access = [ln for ln in lines if ln["logger"] == "access"]
    assert len(access) == 1  # /health is quiet
    assert access[0]["request_id"] == "trace-42" and access[0]["route"] == "/v1/x" and access[0]["status"] == 200
    assert "secret" not in json.dumps(access[0])
