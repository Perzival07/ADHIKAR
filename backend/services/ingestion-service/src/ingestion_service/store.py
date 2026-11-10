from __future__ import annotations

import re
import uuid

from qdrant_client import AsyncQdrantClient, models

from .config import Settings

KEYWORD_FIELDS = ["scheme_id", "state_scope", "gender_eligibility", "income_ceiling", "language", "status", "category"]
INT_FIELDS = ["min_age", "max_age"]
BOOL_FIELDS = ["is_central", "flagged"]


def collection_name(prefix: str, model_id: str) -> str:
    return f"{prefix}__{re.sub(r'[^A-Za-z0-9_.-]', '_', model_id)}"


def point_id(chunk_id: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, chunk_id))


def make_client(s: Settings) -> AsyncQdrantClient:
    if s.qdrant_url == ":memory:":
        return AsyncQdrantClient(":memory:")
    return AsyncQdrantClient(url=s.qdrant_url, api_key=s.qdrant_api_key or None)


class Store:
    def __init__(self, client: AsyncQdrantClient):
        self.client = client

    async def ensure_collection(self, name: str, dim: int) -> None:
        if await self.client.collection_exists(name):
            return
        await self.client.create_collection(name, vectors_config=models.VectorParams(size=dim, distance=models.Distance.COSINE))
        for f in KEYWORD_FIELDS:
            await self.client.create_payload_index(name, f, models.PayloadSchemaType.KEYWORD)
        for f in INT_FIELDS:
            await self.client.create_payload_index(name, f, models.PayloadSchemaType.INTEGER)
        for f in BOOL_FIELDS:
            await self.client.create_payload_index(name, f, models.PayloadSchemaType.BOOL)

    async def upsert(self, name: str, ids: list[str], vectors: list[list[float]], payloads: list[dict]) -> None:
        points = [models.PointStruct(id=point_id(i), vector=v, payload=p) for i, v, p in zip(ids, vectors, payloads, strict=True)]
        for i in range(0, len(points), 128):
            await self.client.upsert(name, points[i : i + 128], wait=True)

    async def delete_chunks(self, name: str, chunk_ids: list[str]) -> None:
        if not chunk_ids or not await self.client.collection_exists(name):
            return
        await self.client.delete(name, models.PointIdsList(points=[point_id(c) for c in chunk_ids]), wait=True)

    async def delete_scheme(self, name: str, scheme_id: str) -> None:
        if not await self.client.collection_exists(name):
            return
        flt = models.Filter(must=[models.FieldCondition(key="scheme_id", match=models.MatchValue(value=scheme_id))])
        await self.client.delete(name, models.FilterSelector(filter=flt), wait=True)

    async def count(self, name: str) -> int:
        if not await self.client.collection_exists(name):
            return 0
        return (await self.client.count(name, exact=True)).count

    async def healthy(self) -> bool:
        try:
            await self.client.get_collections()
            return True
        except Exception:  # noqa: BLE001 - any failure means "not healthy"
            return False
