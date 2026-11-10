from __future__ import annotations

import logging
import time

from starlette.types import ASGIApp, Message, Receive, Scope, Send

log = logging.getLogger("access")
QUIET_PATHS = {"/health", "/ready", "/metrics"}


class AccessLogMiddleware:
    """One structured INFO line per request (method, route, status, ms). The JSON formatter adds the request id,
    so a single X-Request-ID can be followed through every service. Query strings are never logged."""

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["path"] in QUIET_PATHS:
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
            route = getattr(scope.get("route"), "path", None) or scope["path"]
            log.info("request", extra={"fields": {"method": scope["method"], "route": route, "status": status["code"],
                                                  "ms": int((time.perf_counter() - t0) * 1000)}})
