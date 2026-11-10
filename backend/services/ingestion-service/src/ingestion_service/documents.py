"""Discover documents in the folder and resolve scheme metadata (layouts: file-per-scheme, folder-per-scheme)."""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from .loaders import SUPPORTED, Loaded, load_file

LANG_CODES = {
    "en", "hi", "as", "bn", "brx", "doi", "gu", "kn", "ks", "kok", "mai", "ml", "mni", "mr", "ne", "or",
    "pa", "sa", "sat", "sd", "ta", "te", "ur",
}
META_FIELDS = {
    "scheme_id", "name", "state_scope", "is_central", "category", "gender_eligibility", "income_ceiling",
    "min_age", "max_age", "education_level", "official_portal_url", "last_verified_date", "language",
    "source_type", "status",
}
_LANG_SUFFIX = re.compile(r"^(?P<stem>.+)\.(?P<lang>[a-z]{2,3})$")


@dataclass
class Document:
    path: Path
    rel: str  # path relative to docs root (stable id of the source)
    scheme_id: str
    meta: dict[str, Any]
    loaded: Loaded
    content_hash: str


def split_lang(stem: str) -> tuple[str, str | None]:
    m = _LANG_SUFFIX.match(stem)
    if m and m.group("lang") in LANG_CODES:
        return m.group("stem"), m.group("lang")
    return stem, None


def _read_meta_yaml(p: Path) -> dict[str, Any]:
    data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise TypeError(f"{p.name} must contain a YAML mapping")
    return data


def _normalise(meta: dict[str, Any], scheme_id: str, language: str, source_type: str, verified: bool) -> dict[str, Any]:
    out = {k: v for k, v in meta.items() if k in META_FIELDS or k in {"application_status", "deadline", "is_expired", "announced_date", "ministry", "department"}}
    out.setdefault("scheme_id", scheme_id)
    out.setdefault("name", scheme_id)
    out.setdefault("language", language)
    out.setdefault("source_type", source_type)
    out["status"] = out.get("status", "verified") if verified else "unverified"
    return out


def iter_documents(root: Path, only: Path | None = None) -> list[tuple[Path, str]]:
    """Return [(path, rel)] for every supported file (skipping README.md and meta.yaml)."""
    scope = (only or root).resolve()
    out = []
    for p in sorted(scope.rglob("*") if scope.is_dir() else [scope]):
        if not p.is_file() or p.suffix.lower() not in SUPPORTED:
            continue
        if p.parent == root and p.name.lower() == "readme.md":
            continue
        out.append((p, p.relative_to(root.resolve()).as_posix()))
    return out


def load_document(root: Path, path: Path, rel: str) -> Document:
    root = root.resolve()
    parent = path.parent.resolve()
    stem, lang = split_lang(path.stem)
    raw = path.read_bytes()
    h = hashlib.sha256(raw)

    folder_meta: dict[str, Any] | None = None
    scheme_id = stem
    if parent != root:  # folder-per-scheme: <scheme_id>/<file>
        scheme_id = parent.relative_to(root).parts[0]
        meta_file = root / scheme_id / "meta.yaml"
        if meta_file.exists():
            folder_meta = _read_meta_yaml(meta_file)
            h.update(meta_file.read_bytes())

    loaded = load_file(path)
    meta_src = {**(folder_meta or {}), **(loaded.front_matter or {})}
    has_meta = bool(meta_src)
    source_type = {".pdf": "pdf", ".html": "web", ".htm": "web"}.get(path.suffix.lower(), "manual")
    scheme_id = str(meta_src.get("scheme_id", scheme_id))
    meta = _normalise(meta_src, scheme_id, lang or str(meta_src.get("language", "en")), meta_src.get("source_type", source_type), has_meta)
    meta["language"] = lang or meta.get("language", "en")
    return Document(path, rel, scheme_id, meta, loaded, h.hexdigest())
