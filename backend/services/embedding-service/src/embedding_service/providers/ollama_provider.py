from __future__ import annotations

import httpx

from .base import EmbeddingProvider


class EmbeddingUnavailable(Exception):
    pass


class OllamaEmbeddingProvider(EmbeddingProvider):
    name = "ollama"

    def __init__(self, base_url: str, model: str, client: httpx.AsyncClient | None = None, timeout: float = 60.0,
                 query_prefix: str = "", document_prefix: str = ""):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.client = client or httpx.AsyncClient(timeout=timeout)
        self.query_prefix = query_prefix
        self.document_prefix = document_prefix
        self._dim: int | None = None

    async def embed(self, texts: list[str], kind: str) -> list[list[float]]:
        prefix = self.query_prefix if kind == "query" else self.document_prefix
        try:
            r = await self.client.post(f"{self.base_url}/api/embed", json={"model": self.model, "input": [prefix + t for t in texts]})
        except httpx.HTTPError as e:
            raise EmbeddingUnavailable(f"ollama unreachable: {e.__class__.__name__}") from e
        if r.status_code != 200:
            raise EmbeddingUnavailable(f"ollama returned {r.status_code}: {r.text[:200]}")
        vecs = r.json().get("embeddings")
        if not vecs or len(vecs) != len(texts):
            raise EmbeddingUnavailable("unexpected ollama embed response")
        self._dim = len(vecs[0])
        return vecs

    async def info(self) -> tuple[str, int]:
        if self._dim is None:
            await self.embed(["dim probe"], "query")
        return f"ollama-{self.model.replace(':', '_')}-{self._dim}", int(self._dim or 0)

    async def ready(self) -> tuple[bool, str]:
        if not self.model:
            return False, "EMBED_OLLAMA_MODEL is not set"
        try:
            r = await self.client.get(f"{self.base_url}/api/tags", timeout=3.0)
            return (r.status_code == 200), ("ok" if r.status_code == 200 else f"ollama returned {r.status_code}")
        except httpx.HTTPError:
            return False, "ollama is not reachable"

    async def aclose(self) -> None:
        await self.client.aclose()
