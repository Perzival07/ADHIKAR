from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx

from ..errors import ProviderBadResponse, ProviderTimeout, ProviderUnavailable
from .base import Capabilities, LLMProvider, ProviderRequest, ProviderResult


class OllamaProvider(LLMProvider):
    name = "ollama"

    def __init__(self, base_url: str, options: dict | None = None, client: httpx.AsyncClient | None = None,
                 connect_timeout: float = 5.0, read_timeout: float = 120.0):
        self.base_url = base_url.rstrip("/")
        self.options = options or {}
        self.client = client or httpx.AsyncClient(timeout=httpx.Timeout(read_timeout, connect=connect_timeout))
        self.capabilities = Capabilities(
            supports_json_schema=True, supports_streaming=True, max_context=self.options.get("num_ctx", 4096)
        )

    def _payload(self, req: ProviderRequest, stream: bool) -> dict:
        opts = {k: v for k, v in self.options.items() if k in {"num_ctx", "num_gpu", "top_p", "top_k", "seed"}}
        opts["num_predict"] = req.max_tokens
        if req.temperature is not None:
            opts["temperature"] = req.temperature
        payload: dict = {"model": req.model, "messages": req.messages, "stream": stream, "options": opts}
        if "keep_alive" in self.options:
            payload["keep_alive"] = self.options["keep_alive"]
        if req.json_schema is not None:
            payload["format"] = req.json_schema
        return payload

    def _map(self, exc: Exception) -> Exception:
        if isinstance(exc, httpx.TimeoutException):
            return ProviderTimeout(f"ollama timed out: {exc.__class__.__name__}")
        if isinstance(exc, httpx.HTTPError):
            return ProviderUnavailable(f"ollama unreachable: {exc.__class__.__name__}")
        return exc

    async def chat(self, req: ProviderRequest) -> ProviderResult:
        try:
            r = await self.client.post(f"{self.base_url}/api/chat", json=self._payload(req, False))
        except httpx.HTTPError as e:
            raise self._map(e) from e
        if r.status_code >= 500:
            raise ProviderUnavailable(f"ollama returned {r.status_code}")
        if r.status_code >= 400:
            raise ProviderBadResponse(f"ollama rejected request: {r.status_code} {r.text[:200]}")
        data = r.json()
        try:
            text = data["message"]["content"]
        except (KeyError, TypeError) as e:
            raise ProviderBadResponse("unexpected ollama response shape") from e
        return ProviderResult(text, data.get("prompt_eval_count", 0), data.get("eval_count", 0))

    async def stream(self, req: ProviderRequest) -> AsyncIterator[str]:
        try:
            async with self.client.stream("POST", f"{self.base_url}/api/chat", json=self._payload(req, True)) as r:
                if r.status_code >= 400:
                    raise ProviderUnavailable(f"ollama returned {r.status_code}")
                async for line in r.aiter_lines():
                    if not line.strip():
                        continue
                    obj = json.loads(line)
                    delta = obj.get("message", {}).get("content", "")
                    if delta:
                        yield delta
                    if obj.get("done"):
                        break
        except httpx.HTTPError as e:
            raise self._map(e) from e

    async def health(self) -> bool:
        try:
            return (await self.client.get(f"{self.base_url}/api/tags", timeout=3.0)).status_code == 200
        except httpx.HTTPError:
            return False

    async def aclose(self) -> None:
        await self.client.aclose()
