from __future__ import annotations

import json
from collections.abc import AsyncIterator
from typing import Any

import httpx
from haqdaar_common import CircuitBreaker, CircuitOpen, outbound_headers

from .config import Settings
from .contract_models import (
    ChatRequest,
    ChatResponse,
    Chunk,
    CitizenProfile,
    EligibilityRequest,
    EligibilityResponse,
    EligibilityResult,
    SearchFilters,
    SearchRequest,
    SearchResponse,
)


class DependencyError(Exception):
    """A downstream service failed. `kind` says which, `status` is its HTTP status if any."""

    def __init__(self, service: str, message: str, status: int | None = None, circuit: bool = False):
        super().__init__(f"{service}: {message}")
        self.service, self.message, self.status, self.circuit = service, message, status, circuit


class Clients:
    SERVICES = ("eligibility-service", "retrieval-service", "llm-gateway")

    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None, on_circuit_open=None, clock=None):
        self.s = settings
        self.http = httpx.AsyncClient(timeout=settings.dependency_timeout, transport=transport)
        kw = {"clock": clock} if clock else {}
        self.breakers = {
            name: CircuitBreaker(name, settings.breaker_threshold, settings.breaker_reset, on_open=on_circuit_open, **kw)
            for name in self.SERVICES
        }

    def _guard(self, service: str) -> CircuitBreaker:
        br = self.breakers[service]
        try:
            br.before_call()
        except CircuitOpen as e:
            raise DependencyError(service, "circuit open (recent failures); not calling", circuit=True) from e
        return br

    async def _post(self, service: str, url: str, body: dict[str, Any], timeout: float | None = None) -> dict[str, Any]:
        br = self._guard(service)
        try:
            r = await self.http.post(url, json=body, headers=outbound_headers(), timeout=timeout or self.s.dependency_timeout)
        except httpx.TimeoutException as e:
            br.record_failure()
            raise DependencyError(service, "timed out", 504) from e
        except httpx.HTTPError as e:
            br.record_failure()
            raise DependencyError(service, f"unreachable ({e.__class__.__name__})") from e
        # 5xx = the dependency is unhealthy; anything else (incl. 4xx / 429 "busy") means it is alive.
        br.record_failure() if r.status_code >= 500 else br.record_success()
        if r.status_code != 200:
            detail = ""
            try:
                detail = str(r.json().get("detail", ""))[:200]
            except (ValueError, AttributeError):
                detail = r.text[:200]
            raise DependencyError(service, f"HTTP {r.status_code} {detail}".strip(), r.status_code)
        return r.json()

    async def eligibility(self, profile: CitizenProfile, scheme_ids: list[str] | None = None) -> list[EligibilityResult]:
        body = EligibilityRequest(profile=profile, scheme_ids=scheme_ids).model_dump(mode="json")
        data = await self._post("eligibility-service", f"{self.s.eligibility_url.rstrip('/')}/v1/eligibility", body)
        return EligibilityResponse(**data).results

    async def search(self, query: str, scheme_ids: list[str], state: str, language: str,
                     top_k: int | None = None, per_scheme: int | None = None) -> list[Chunk]:
        body = SearchRequest(
            query=query, top_k=top_k or self.s.retrieval_top_k, max_chunks_per_scheme=per_scheme or self.s.chunks_per_scheme,
            filters=SearchFilters(scheme_ids=scheme_ids, state=state, language=language),
        ).model_dump(mode="json")
        data = await self._post("retrieval-service", f"{self.s.retrieval_url.rstrip('/')}/v1/search", body)
        return SearchResponse(**data).chunks

    async def chat(self, req: ChatRequest, timeout: float) -> ChatResponse:
        data = await self._post("llm-gateway", f"{self.s.llm_gateway_url.rstrip('/')}/v1/chat", req.model_dump(mode="json"), timeout)
        return ChatResponse(**data)

    async def chat_stream(self, req: ChatRequest, timeout: float) -> AsyncIterator[str]:
        """Yield text deltas from llm-gateway's SSE stream."""
        body = req.model_copy(update={"stream": True}).model_dump(mode="json")
        br = self._guard("llm-gateway")
        try:
            async with self.http.stream("POST", f"{self.s.llm_gateway_url.rstrip('/')}/v1/chat", json=body,
                                        headers=outbound_headers(), timeout=timeout) as r:
                if r.status_code != 200:
                    br.record_failure() if r.status_code >= 500 else br.record_success()
                    raise DependencyError("llm-gateway", f"HTTP {r.status_code}", r.status_code)
                br.record_success()
                event = None
                async for line in r.aiter_lines():
                    if line.startswith("event:"):
                        event = line[6:].strip()
                    elif line.startswith("data:"):
                        payload = json.loads(line[5:].strip())
                        if event == "error":
                            raise DependencyError("llm-gateway", str(payload.get("detail")), payload.get("status"))
                        if event in (None, "message") and "delta" in payload:
                            yield payload["delta"]
                        event = None
        except httpx.TimeoutException as e:
            br.record_failure()
            raise DependencyError("llm-gateway", "timed out", 504) from e
        except httpx.HTTPError as e:
            br.record_failure()
            raise DependencyError("llm-gateway", f"unreachable ({e.__class__.__name__})") from e

    async def aclose(self) -> None:
        await self.http.aclose()
