from __future__ import annotations

import logging
from typing import Any

import httpx
from haqdaar_common import CircuitBreaker, CircuitOpen, outbound_headers
from qdrant_client import AsyncQdrantClient, models

from .config import Settings
from .contract_models import Chunk, SchemeDocMeta, SearchFilters, SearchRequest
from .fusion import bm25_rank, rrf
from .reranker import Reranker

log = logging.getLogger("retrieval_service")

META_KEYS = list(SchemeDocMeta.model_fields)


class SearchUnavailable(Exception):
    """A dependency (Qdrant / embedding-service / index) is not usable. Maps to HTTP 503."""


def collection_name(prefix: str, model_id: str) -> str:
    import re

    return f"{prefix}__{re.sub(r'[^A-Za-z0-9_.-]', '_', model_id)}"


def build_filter(f: SearchFilters) -> models.Filter:
    must: list[Any] = [models.FieldCondition(key="status", match=models.MatchValue(value="verified"))]
    if f.scheme_ids is not None:
        must.append(models.FieldCondition(key="scheme_id", match=models.MatchAny(any=f.scheme_ids)))
    if f.state and f.state != "All India":
        region: list[Any] = [
            models.FieldCondition(key="state_scope", match=models.MatchValue(value="All")),
            models.FieldCondition(key="state_scope", match=models.MatchValue(value=f.state)),
        ]
        if f.include_central:
            region.append(models.FieldCondition(key="is_central", match=models.MatchValue(value=True)))
        must.append(models.Filter(should=region))
    if f.language:
        langs = list(dict.fromkeys([f.language, "en"]))
        must.append(models.FieldCondition(key="language", match=models.MatchAny(any=langs)))
    return models.Filter(must=must)


def to_chunk(payload: dict[str, Any], score: float = 0.0) -> Chunk:
    meta = {k: payload[k] for k in META_KEYS if k in payload and payload[k] is not None}
    try:
        m = SchemeDocMeta(**meta)
    except Exception:  # noqa: BLE001 - tolerate odd payloads; chunk text is still useful
        m = None
    return Chunk(
        chunk_id=payload["chunk_id"], scheme_id=payload["scheme_id"], text=payload.get("text", ""),
        section=payload.get("section", "") or "", page=payload.get("page"), source=payload.get("source", "") or "",
        meta=m, score=score, flagged=bool(payload.get("flagged", False)),
    )


def prefer_language(chunks: list[Chunk], language: str | None) -> list[Chunk]:
    """Per scheme: keep chunks in the preferred language if any exist, otherwise fall back to what is there (English)."""
    if not language:
        return chunks
    has_pref = {c.scheme_id for c in chunks if c.meta and c.meta.language == language}
    return [c for c in chunks if c.scheme_id not in has_pref or (c.meta and c.meta.language == language)]


def diversify(chunks: list[Chunk], top_k: int, per_scheme: int) -> list[Chunk]:
    out: list[Chunk] = []
    count: dict[str, int] = {}
    for c in chunks:
        if count.get(c.scheme_id, 0) >= per_scheme:
            continue
        count[c.scheme_id] = count.get(c.scheme_id, 0) + 1
        out.append(c)
        if len(out) >= top_k:
            break
    return out


class Searcher:
    def __init__(self, settings: Settings, qdrant: AsyncQdrantClient, http: httpx.AsyncClient, reranker: Reranker):
        self.s, self.qdrant, self.http, self.reranker = settings, qdrant, http, reranker
        self.embed_breaker = CircuitBreaker("embedding-service", settings.breaker_threshold, settings.breaker_reset)

    async def _embed_query(self, query: str) -> tuple[list[float], str]:
        try:
            self.embed_breaker.before_call()
        except CircuitOpen as e:
            raise SearchUnavailable("embedding-service circuit open (recent failures); not calling") from e
        try:
            r = await self.http.post(
                f"{self.s.embedding_url.rstrip('/')}/v1/embed", json={"texts": [query], "kind": "query"}, headers=outbound_headers()
            )
        except httpx.HTTPError as e:
            self.embed_breaker.record_failure()
            raise SearchUnavailable(f"embedding-service unreachable: {e.__class__.__name__}") from e
        self.embed_breaker.record_failure() if r.status_code >= 500 else self.embed_breaker.record_success()
        if r.status_code != 200:
            raise SearchUnavailable(f"embedding-service returned {r.status_code}")
        d = r.json()
        return d["vectors"][0], d["model_id"]

    async def search(self, req: SearchRequest) -> list[Chunk]:
        vector, model_id = await self._embed_query(req.query)
        name = collection_name(self.s.collection_prefix, model_id)
        flt = build_filter(req.filters)
        try:
            if not await self.qdrant.collection_exists(name):
                raise SearchUnavailable(f"index {name!r} does not exist; run ingestion for the current embedding model")
            sem = await self.qdrant.query_points(name, query=vector, query_filter=flt, limit=self.s.pool, with_payload=True)
            scanned = await self._scan(name, flt)
        except SearchUnavailable:
            raise
        except Exception as e:
            raise SearchUnavailable(f"vector store error: {e.__class__.__name__}: {e}") from e

        payloads: dict[str, dict[str, Any]] = {}
        sem_ids: list[str] = []
        for p in sem.points:
            pl = p.payload or {}
            payloads[pl["chunk_id"]] = pl
            sem_ids.append(pl["chunk_id"])
        for pl in scanned:
            payloads.setdefault(pl["chunk_id"], pl)

        kw = bm25_rank(req.query, {pl["chunk_id"]: pl.get("text", "") for pl in scanned})
        kw_ids = [cid for cid, _ in kw][: self.s.pool]

        fused = rrf([(self.s.weight_semantic, sem_ids), (self.s.weight_keyword, kw_ids)], self.s.rrf_k)
        ranked = sorted(fused, key=lambda cid: (-fused[cid], cid))
        chunks = [to_chunk(payloads[cid], fused[cid]) for cid in ranked]
        chunks = prefer_language(chunks, req.filters.language)

        if self.s.reranker != "none":
            head = chunks[: self.s.rerank_candidates]
            chunks = [*(await self.reranker.rerank(req.query, head)), *chunks[self.s.rerank_candidates:]]
        return diversify(chunks, req.top_k, req.max_chunks_per_scheme)

    async def _scan(self, name: str, flt: models.Filter) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        offset = None
        while len(out) < self.s.keyword_scan_limit:
            res, offset = await self.qdrant.scroll(name, scroll_filter=flt, limit=512, offset=offset, with_payload=True)
            out.extend(r.payload or {} for r in res)
            if offset is None:
                break
        return out

    async def collections_ok(self) -> bool:
        try:
            await self.qdrant.get_collections()
            return True
        except Exception:  # noqa: BLE001
            return False

    async def embedding_ready(self) -> bool:
        try:
            return (await self.http.get(f"{self.s.embedding_url.rstrip('/')}/ready", timeout=3.0)).status_code == 200
        except httpx.HTTPError:
            return False
