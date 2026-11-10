from __future__ import annotations

import json
import logging
from abc import ABC, abstractmethod

import httpx
from haqdaar_common import outbound_headers

from .contract_models import Chunk

log = logging.getLogger("retrieval_service")


class Reranker(ABC):
    @abstractmethod
    async def rerank(self, query: str, chunks: list[Chunk]) -> list[Chunk]: ...


class NoopReranker(Reranker):
    async def rerank(self, query: str, chunks: list[Chunk]) -> list[Chunk]:
        return chunks


class GatewayReranker(Reranker):
    """Scores candidates with an LLM via llm-gateway (alias only; no vendor knowledge here).
    On any failure the original order is kept, so reranking can never break search."""

    def __init__(self, base_url: str, alias: str, client: httpx.AsyncClient):
        self.base_url, self.alias, self.client = base_url.rstrip("/"), alias, client

    async def rerank(self, query: str, chunks: list[Chunk]) -> list[Chunk]:
        if len(chunks) < 2:
            return chunks
        listing = "\n".join(f"[{i}] {c.text[:400]}" for i, c in enumerate(chunks))
        schema = {
            "type": "object",
            "properties": {"scores": {"type": "array", "items": {"type": "number", "minimum": 0, "maximum": 10}}},
            "required": ["scores"],
        }
        body = {
            "model_alias": self.alias,
            "messages": [
                {"role": "system", "content": "Rate how relevant each passage is to the query from 0 to 10. Return JSON {\"scores\": [...]} with one number per passage, in order."},
                {"role": "user", "content": f"Query: {query}\n\nPassages:\n{listing}"},
            ],
            "json_schema": schema,
            "max_tokens": 256,
            "temperature": 0,
        }
        try:
            r = await self.client.post(f"{self.base_url}/v1/chat", json=body, headers=outbound_headers())
            r.raise_for_status()
            scores = r.json()["json"]["scores"]
            if len(scores) != len(chunks):
                raise ValueError("score count mismatch")
        except (httpx.HTTPError, KeyError, TypeError, ValueError, json.JSONDecodeError) as e:
            log.warning("rerank skipped: %s", e)
            return chunks
        order = sorted(range(len(chunks)), key=lambda i: (-scores[i], i))
        return [chunks[i] for i in order]
