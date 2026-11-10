from __future__ import annotations

import contextvars
import uuid

from starlette.types import ASGIApp, Message, Receive, Scope, Send

HEADER = "x-request-id"
_request_id: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")


def get_request_id() -> str:
    return _request_id.get()


def outbound_headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    """Headers to attach to outbound httpx calls so the id propagates."""
    headers = {"X-Request-ID": get_request_id()}
    if extra:
        headers.update(extra)
    return headers


class RequestIDMiddleware:
    """Reads or generates X-Request-ID, stores it in a contextvar, echoes it back."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        rid = None
        for k, v in scope.get("headers", []):
            if k.decode("latin-1").lower() == HEADER:
                rid = v.decode("latin-1")[:128]
                break
        rid = rid or uuid.uuid4().hex
        token = _request_id.set(rid)

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.append((b"x-request-id", rid.encode("latin-1")))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            _request_id.reset(token)
