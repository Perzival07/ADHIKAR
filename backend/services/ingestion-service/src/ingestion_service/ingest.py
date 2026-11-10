from __future__ import annotations

import asyncio
import logging
import time
from pathlib import Path

from haqdaar_common import Registry

from .chunker import chunk_id, chunk_section
from .config import Settings
from .contract_models import FileError, IngestStatus
from .documents import iter_documents, load_document
from .embedding_client import EmbeddingClient, EmbeddingError
from .injection import looks_like_instructions
from .manifest import Manifest, ManifestRow
from .store import Store, collection_name

log = logging.getLogger("ingestion_service")


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Ingestor:
    def __init__(self, settings: Settings, store: Store, embedder: EmbeddingClient, manifest: Manifest):
        self.s = settings
        self.store = store
        self.embedder = embedder
        self.manifest = manifest
        self.status = IngestStatus()
        self.metrics = Registry()
        self._model: tuple[str, int] | None = None  # (collection, dim)
        self._lock = asyncio.Lock()  # one run at a time (watch mode + POST /v1/ingest + CLI)

    @property
    def root(self) -> Path:
        return Path(self.s.docs_dir).resolve()

    def resolve_scope(self, path: str | None) -> Path | None:
        """A requested sub-path must stay inside the docs root (no path traversal)."""
        if not path:
            return None
        p = (self.root / path).resolve() if not Path(path).is_absolute() else Path(path).resolve()
        if p != self.root and self.root not in p.parents:
            raise ValueError("path must be inside the documents folder")
        if not p.exists():
            raise ValueError(f"path does not exist: {path}")
        return p

    async def _collection(self) -> tuple[str, int]:
        if self._model is None:
            _, model_id, dim = await self.embedder.embed(["dimension probe"], "document")
            name = collection_name(self.s.collection_prefix, model_id)
            await self.store.ensure_collection(name, dim)
            self._model = (name, dim)
        return self._model

    def _payload(self, doc, rc, cid) -> dict:
        m = doc.meta
        payload = {k: m.get(k) for k in (
            "scheme_id", "name", "state_scope", "is_central", "category", "gender_eligibility", "income_ceiling",
            "min_age", "max_age", "education_level", "official_portal_url", "last_verified_date", "language",
            "source_type", "status",
        )}
        payload.update(
            chunk_id=cid, text=rc.text, section=rc.section, page=rc.page, source=doc.rel, flagged=looks_like_instructions(rc.text)
        )
        return payload

    async def run(self, path: str | None = None, force: bool = False) -> IngestStatus:
        async with self._lock:
            return await self._run(path, force)

    async def _run(self, path: str | None, force: bool) -> IngestStatus:
        st = self.status = IngestStatus(state="running", started_at=_now())
        try:
            scope = self.resolve_scope(path)
            name, _dim = await self._collection()
            st.collection = name
            files = iter_documents(self.root, scope)
            st.files_total = len(files)
            seen: set[str] = set()

            for fpath, rel in files:
                seen.add(rel)
                try:
                    doc = load_document(self.root, fpath, rel)
                    row = self.manifest.get(rel)
                    if row and row.content_hash == doc.content_hash and row.collection == name and not force:
                        st.files_unchanged += 1
                        continue
                    added, deleted = await self._ingest_doc(doc, row, name)
                    st.files_processed += 1
                    st.chunks_added += added
                    st.chunks_deleted += deleted
                except (EmbeddingError, Exception) as e:  # noqa: BLE001 - per-file isolation
                    log.error("ingest failed for %s: %s", rel, e)
                    st.errors.append(FileError(file=rel, error=str(e)))

            # deletions: files in the manifest (within scope) that no longer exist
            for row in self.manifest.all():
                in_scope = scope is None or (self.root / row.rel).resolve() == scope or scope in (self.root / row.rel).resolve().parents
                if in_scope and row.rel not in seen:
                    await self.store.delete_chunks(row.collection, row.chunk_ids)
                    self.manifest.delete(row.rel)
                    st.files_processed += 1
                    st.chunks_deleted += len(row.chunk_ids)
            st.state = "done" if not st.errors else "error"
        except Exception as e:
            log.exception("ingestion run failed")
            st.errors.append(FileError(file="*", error=str(e)))
            st.state = "error"
        st.finished_at = _now()
        self.metrics.counter("ingest_runs_total", "Ingestion runs", ("state",)).inc(state=st.state)
        self.metrics.counter("ingest_chunks_added_total", "Chunks added", ()).inc(st.chunks_added)
        self.metrics.counter("ingest_chunks_deleted_total", "Chunks deleted", ()).inc(st.chunks_deleted)
        self.metrics.counter("ingest_file_errors_total", "Files that failed to ingest", ()).inc(len(st.errors))
        return st

    async def _ingest_doc(self, doc, old: ManifestRow | None, name: str) -> tuple[int, int]:
        raw = []
        for sec in doc.loaded.sections:
            raw.extend(chunk_section(sec, self.s.chunk_tokens, self.s.chunk_overlap))
        ids = [chunk_id(doc.scheme_id, doc.rel, rc.text) for rc in raw]
        # de-duplicate identical chunks inside a file
        uniq = list(dict.fromkeys(ids))
        by_id = dict(zip(ids, raw, strict=True))
        raw_u = [by_id[i] for i in uniq]
        vectors, _, _ = await self.embedder.embed([rc.text for rc in raw_u], "document") if raw_u else ([], "", 0)
        deleted = 0
        if old:
            await self.store.delete_chunks(old.collection, old.chunk_ids)
            deleted = len(old.chunk_ids)
        if raw_u:
            await self.store.upsert(name, uniq, vectors, [self._payload(doc, rc, cid) for rc, cid in zip(raw_u, uniq, strict=True)])
        self.manifest.put(ManifestRow(doc.rel, doc.content_hash, doc.scheme_id, uniq, name))
        return len(uniq), deleted

    async def delete_scheme(self, scheme_id: str) -> int:
        name, _ = await self._collection()
        n = 0
        for row in self.manifest.by_scheme(scheme_id):
            n += len(row.chunk_ids)
            self.manifest.delete(row.rel)
        await self.store.delete_scheme(name, scheme_id)
        return n
