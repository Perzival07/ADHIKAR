from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx

from ..errors import ProviderBadResponse, ProviderTimeout, ProviderUnavailable
from .base import Capabilities, LLMProvider, ProviderRequest, ProviderResult


class OpenAICompatibleProvider(LLMProvider):
    """Any server exposing /v1/chat/completions (llama.cpp server, LM Studio, vLLM)."""

    name = "openai_compatible"

    def __init__(self, base_url: str, options: dict | None = None, client: httpx.AsyncClient | None = None,
                 connect_timeout: float = 5.0, read_timeout: float = 120.0):
        self.base_url = base_url.rstrip("/")
        self.options = options or {}
        self.client = client or httpx.AsyncClient(timeout=httpx.Timeout(read_timeout, connect=connect_timeout))
        self.capabilities = Capabilities(
            supports_json_schema=bool(self.options.get("supports_json_schema", False)),
            supports_streaming=True,
            max_context=self.options.get("max_context"),
        )

    def _payload(self, req: ProviderRequest, stream: bool) -> dict:
        payload: dict = {"model": req.model, "messages": req.messages, "max_tokens": req.max_tokens, "stream": stream}
        if req.temperature is not None:
            payload["temperature"] = req.temperature
        if req.json_schema is not None and self.capabilities.supports_json_schema:
            payload["response_format"] = {
                "type": "json_schema",
                "json_schema": {"name": "output", "schema": req.json_schema, "strict": True},
            }
        return payload

    def _map(self, e: httpx.HTTPError) -> Exception:
        if isinstance(e, httpx.TimeoutException):
            return ProviderTimeout("openai-compatible server timed out")
        return ProviderUnavailable(f"openai-compatible server unreachable: {e.__class__.__name__}")

    async def chat(self, req: ProviderRequest) -> ProviderResult:
        try:
            r = await self.client.post(f"{self.base_url}/v1/chat/completions", json=self._payload(req, False))
        except httpx.HTTPError as e:
            raise self._map(e) from e
        if r.status_code >= 500:
            raise ProviderUnavailable(f"server returned {r.status_code}")
        if r.status_code >= 400:
            raise ProviderBadResponse(f"server rejected request: {r.status_code} {r.text[:200]}")
        data = r.json()
        try:
            text = data["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError) as e:
            raise ProviderBadResponse("unexpected response shape") from e
        u = data.get("usage", {})
        return ProviderResult(text, u.get("prompt_tokens", 0), u.get("completion_tokens", 0))

    async def stream(self, req: ProviderRequest) -> AsyncIterator[str]:
        try:
            async with self.client.stream("POST", f"{self.base_url}/v1/chat/completions", json=self._payload(req, True)) as r:
                if r.status_code >= 400:
                    raise ProviderUnavailable(f"server returned {r.status_code}")
                async for line in r.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    body = line[5:].strip()
                    if body == "[DONE]":
                        break
                    delta = json.loads(body)["choices"][0].get("delta", {}).get("content")
                    if delta:
                        yield delta
        except httpx.HTTPError as e:
            raise self._map(e) from e

    async def health(self) -> bool:
        try:
            return (await self.client.get(f"{self.base_url}/v1/models", timeout=3.0)).status_code == 200
        except httpx.HTTPError:
            return False

    async def aclose(self) -> None:
        await self.client.aclose()
