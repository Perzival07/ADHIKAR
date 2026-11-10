from __future__ import annotations

import httpx
from adhikar_common import CircuitBreaker, CircuitOpen, outbound_headers


class EmbeddingError(Exception):
    pass


class EmbeddingClient:
    """HTTP client for embedding-service (no model code lives here)."""

    def __init__(self, base_url: str, timeout: float = 60.0, batch: int = 32, transport: httpx.AsyncBaseTransport | None = None):
        self.base_url = base_url.rstrip("/")
        self.batch = batch
        self.client = httpx.AsyncClient(timeout=timeout, transport=transport)
        self.breaker = CircuitBreaker("embedding-service", failure_threshold=5, reset_timeout=30.0)

    async def embed(self, texts: list[str], kind: str = "document") -> tuple[list[list[float]], str, int]:
        vectors: list[list[float]] = []
        model_id, dim = "", 0
        for i in range(0, len(texts), self.batch):
            try:
                self.breaker.before_call()
            except CircuitOpen as e:
                raise EmbeddingError("embedding-service circuit open (recent failures); not calling") from e
            try:
                r = await self.client.post(
                    f"{self.base_url}/v1/embed", json={"texts": texts[i : i + self.batch], "kind": kind}, headers=outbound_headers()
                )
            except httpx.HTTPError as e:
                self.breaker.record_failure()
                raise EmbeddingError(f"embedding-service unreachable: {e.__class__.__name__}") from e
            self.breaker.record_failure() if r.status_code >= 500 else self.breaker.record_success()
            if r.status_code != 200:
                raise EmbeddingError(f"embedding-service returned {r.status_code}: {r.text[:200]}")
            d = r.json()
            vectors.extend(d["vectors"])
            model_id, dim = d["model_id"], d["dim"]
        return vectors, model_id, dim

    async def ready(self) -> bool:
        try:
            return (await self.client.get(f"{self.base_url}/ready", timeout=3.0)).status_code == 200
        except httpx.HTTPError:
            return False

    async def aclose(self) -> None:
        await self.client.aclose()
