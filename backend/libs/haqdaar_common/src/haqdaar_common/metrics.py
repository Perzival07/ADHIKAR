"""Dependency-free Prometheus metrics (text exposition format 0.0.4) + an ASGI middleware.

Infrastructure only: counters, histograms, per-request HTTP metrics and a /metrics response.
"""
from __future__ import annotations

import hmac
import threading
import time
from collections.abc import Iterable

from starlette.responses import PlainTextResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

DEFAULT_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0, 120.0)


def _esc(v: str) -> str:
    return str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _labels(names: tuple[str, ...], values: tuple[str, ...], extra: str = "") -> str:
    parts = [f'{n}="{_esc(v)}"' for n, v in zip(names, values, strict=True)]
    if extra:
        parts.append(extra)
    return "{" + ",".join(parts) + "}" if parts else ""


class Counter:
    def __init__(self, name: str, help_: str, labels: tuple[str, ...], lock: threading.Lock):
        self.name, self.help, self.label_names, self._lock = name, help_, labels, lock
        self.values: dict[tuple[str, ...], float] = {}

    def inc(self, amount: float = 1.0, **labels: str) -> None:
        key = tuple(str(labels.get(n, "")) for n in self.label_names)
        with self._lock:
            self.values[key] = self.values.get(key, 0.0) + amount

    def render(self) -> Iterable[str]:
        yield f"# HELP {self.name} {self.help}"
        yield f"# TYPE {self.name} counter"
        for key, v in sorted(self.values.items()):
            yield f"{self.name}{_labels(self.label_names, key)} {v:g}"


class Gauge(Counter):
    def set(self, value: float, **labels: str) -> None:
        key = tuple(str(labels.get(n, "")) for n in self.label_names)
        with self._lock:
            self.values[key] = value

    def render(self) -> Iterable[str]:
        yield f"# HELP {self.name} {self.help}"
        yield f"# TYPE {self.name} gauge"
        for key, v in sorted(self.values.items()):
            yield f"{self.name}{_labels(self.label_names, key)} {v:g}"


class Histogram:
    def __init__(self, name: str, help_: str, labels: tuple[str, ...], buckets: tuple[float, ...], lock: threading.Lock):
        self.name, self.help, self.label_names, self.buckets, self._lock = name, help_, labels, buckets, lock
        self.data: dict[tuple[str, ...], tuple[list[int], float, int]] = {}

    def observe(self, value: float, **labels: str) -> None:
        key = tuple(str(labels.get(n, "")) for n in self.label_names)
        with self._lock:
            counts, total, n = self.data.get(key, ([0] * len(self.buckets), 0.0, 0))
            for i, b in enumerate(self.buckets):
                if value <= b:
                    counts[i] += 1
            self.data[key] = (counts, total + value, n + 1)

    def render(self) -> Iterable[str]:
        yield f"# HELP {self.name} {self.help}"
        yield f"# TYPE {self.name} histogram"
        for key, (counts, total, n) in sorted(self.data.items()):
            for b, c in zip(self.buckets, counts, strict=True):
                yield f"{self.name}_bucket{_labels(self.label_names, key, f'le={chr(34)}{b:g}{chr(34)}')} {c}"
            yield f"{self.name}_bucket{_labels(self.label_names, key, 'le=' + chr(34) + '+Inf' + chr(34))} {n}"
            yield f"{self.name}_sum{_labels(self.label_names, key)} {total:g}"
            yield f"{self.name}_count{_labels(self.label_names, key)} {n}"


class Registry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._metrics: dict[str, Counter | Gauge | Histogram] = {}

    def counter(self, name: str, help_: str = "", labels: tuple[str, ...] = ()) -> Counter:
        with self._lock:
            m = self._metrics.get(name)
            if m is None:
                m = self._metrics[name] = Counter(name, help_ or name, labels, self._lock)
        assert isinstance(m, Counter)
        return m

    def gauge(self, name: str, help_: str = "", labels: tuple[str, ...] = ()) -> Gauge:
        with self._lock:
            m = self._metrics.get(name)
            if m is None:
                m = self._metrics[name] = Gauge(name, help_ or name, labels, self._lock)
        assert isinstance(m, Gauge)
        return m

    def histogram(self, name: str, help_: str = "", labels: tuple[str, ...] = (), buckets: tuple[float, ...] = DEFAULT_BUCKETS) -> Histogram:
        with self._lock:
            m = self._metrics.get(name)
            if m is None:
                m = self._metrics[name] = Histogram(name, help_ or name, labels, buckets, self._lock)
        assert isinstance(m, Histogram)
        return m

    def render(self) -> str:
        with self._lock:
            metrics = list(self._metrics.values())
        lines: list[str] = []
        for m in sorted(metrics, key=lambda x: x.name):
            lines.extend(m.render())
        return "\n".join(lines) + "\n"


class MetricsMiddleware:
    """Records haqdaar_http_requests_total and haqdaar_http_request_duration_seconds per route template."""

    def __init__(self, app: ASGIApp, registry: Registry, service: str):
        self.app, self.service = app, service
        self.requests = registry.counter("haqdaar_http_requests_total", "HTTP requests", ("service", "method", "route", "status"))
        self.duration = registry.histogram("haqdaar_http_request_duration_seconds", "HTTP request duration", ("service", "method", "route"))

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        status = {"code": 500}
        t0 = time.perf_counter()

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                status["code"] = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            if scope["path"] != "/metrics":  # the scrape itself is not counted
                route = getattr(scope.get("route"), "path", None) or "unmatched"  # bounded label cardinality
                method = scope["method"]
                self.requests.inc(service=self.service, method=method, route=route, status=str(status["code"]))
                self.duration.observe(time.perf_counter() - t0, service=self.service, method=method, route=route)


def metrics_response(registry: Registry) -> PlainTextResponse:
    return PlainTextResponse(registry.render(), media_type="text/plain; version=0.0.4; charset=utf-8")


def install_metrics(app, service: str, registry: Registry, token: str = "") -> None:
    """Add per-request HTTP metrics and a GET /metrics endpoint (hidden from OpenAPI).

    If `token` is set the endpoint requires `Authorization: Bearer <token>` (use this on publicly exposed services).
    """
    from starlette.requests import Request
    from starlette.responses import JSONResponse

    app.add_middleware(MetricsMiddleware, registry=registry, service=service)

    async def metrics_endpoint(request: Request):
        if token and not hmac.compare_digest(request.headers.get("authorization", "").encode(), f"Bearer {token}".encode()):
            return JSONResponse({"detail": "metrics require a bearer token"}, status_code=401)
        return metrics_response(registry)

    app.add_route("/metrics", metrics_endpoint, methods=["GET"], include_in_schema=False)
