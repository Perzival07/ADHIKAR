from __future__ import annotations

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class BodyTooLarge(BaseException):
    pass                              # reading the body into HTTP 400, but we need to answer 413.


class BodySizeLimitMiddleware:
    """Reject request bodies larger than `max_bytes` (413), whether or not Content-Length is declared."""

    def __init__(self, app: ASGIApp, max_bytes: int, paths: tuple[str, ...] = ("/v1/",)):
        self.app, self.max_bytes, self.paths = app, max_bytes, paths

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or self.max_bytes <= 0 or not scope["path"].startswith(self.paths):
            await self.app(scope, receive, send)
            return
        for k, v in scope.get("headers", []):
            if k == b"content-length":
                try:
                    if int(v) > self.max_bytes:
                        await self._reject(scope, receive, send)
                        return
                except ValueError:
                    pass
        seen = 0
        started = False

        async def counting_receive() -> Message:
            nonlocal seen
            msg = await receive()
            if msg["type"] == "http.request":
                seen += len(msg.get("body", b""))
                if seen > self.max_bytes:
                    raise BodyTooLarge
            return msg

        async def tracking_send(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, counting_receive, tracking_send)
        except BodyTooLarge:
            if not started:
                await self._reject(scope, receive, send)

    async def _reject(self, scope: Scope, receive: Receive, send: Send) -> None:
        resp = JSONResponse({"detail": f"Request body too large (max {self.max_bytes} bytes)"}, status_code=413)
        await resp(scope, receive, send)
