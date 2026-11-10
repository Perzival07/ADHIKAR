from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ManifestRow:
    rel: str
    content_hash: str
    scheme_id: str
    chunk_ids: list[str]
    collection: str


class Manifest:
    """file -> content hash -> chunk ids (sqlite). Lets re-ingest skip unchanged files and delete stale chunks."""

    def __init__(self, state_dir: str):
        if state_dir == ":memory:":
            path = ":memory:"
        else:
            Path(state_dir).mkdir(parents=True, exist_ok=True)
            path = str(Path(state_dir) / "manifest.sqlite")
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS files (rel TEXT PRIMARY KEY, hash TEXT, scheme_id TEXT, chunk_ids TEXT, collection TEXT)"
        )
        self.db.commit()

    def get(self, rel: str) -> ManifestRow | None:
        r = self.db.execute("SELECT rel, hash, scheme_id, chunk_ids, collection FROM files WHERE rel=?", (rel,)).fetchone()
        return ManifestRow(r[0], r[1], r[2], json.loads(r[3]), r[4]) if r else None

    def put(self, row: ManifestRow) -> None:
        self.db.execute(
            "INSERT OR REPLACE INTO files VALUES (?,?,?,?,?)",
            (row.rel, row.content_hash, row.scheme_id, json.dumps(row.chunk_ids), row.collection),
        )
        self.db.commit()

    def delete(self, rel: str) -> None:
        self.db.execute("DELETE FROM files WHERE rel=?", (rel,))
        self.db.commit()

    def all(self) -> list[ManifestRow]:
        rows = self.db.execute("SELECT rel, hash, scheme_id, chunk_ids, collection FROM files").fetchall()
        return [ManifestRow(r[0], r[1], r[2], json.loads(r[3]), r[4]) for r in rows]

    def by_scheme(self, scheme_id: str) -> list[ManifestRow]:
        return [r for r in self.all() if r.scheme_id == scheme_id]
