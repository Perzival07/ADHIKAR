"""Load scheme metadata (single source of truth: the documents folder front-matter)."""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

log = logging.getLogger("eligibility_service")

LANG_SUFFIX = re.compile(r"\.([a-z]{2,3})$")
KNOWN_LANGS = {"as", "bn", "brx", "doi", "gu", "hi", "kn", "ks", "kok", "mai", "ml", "mni", "mr", "ne", "or", "pa", "sa", "sat", "sd", "ta", "te", "ur"}
_FM = re.compile(r"\A---\s*\n(.*?)\n---\s*\n?", re.DOTALL)
_H2 = re.compile(r"^##\s+(.*\S)\s*$", re.MULTILINE)


@dataclass
class SchemeInfo:
    id: str
    name: str
    category: str = ""
    state_scope: str = "All"
    is_central: bool = True
    gender_eligibility: str = "All"
    income_ceiling: str = "No Limit"
    education_level: str = "All"
    min_age: int | None = None
    max_age: int | None = None
    application_status: str = ""
    is_expired: bool = False
    status: str = "verified"
    summary: str = ""
    default_reason: str = ""

    def text(self, field: str) -> str:
        return str(getattr(self, field, "") or "").lower()


def _sections(body: str) -> dict[str, str]:
    ms = list(_H2.finditer(body))
    out = {}
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(body)
        out[m.group(1).strip().lower()] = body[m.end():end].strip()
    return out


def _from_meta(meta: dict[str, Any], body: str = "") -> SchemeInfo:
    secs = _sections(body)
    elig = secs.get("eligibility", "")
    first_para = elig.split("\n\n")[0].strip() if elig else ""
    return SchemeInfo(
        id=str(meta["scheme_id"]),
        name=str(meta.get("name", meta["scheme_id"])),
        category=str(meta.get("category", "") or ""),
        state_scope=str(meta.get("state_scope", "All") or "All"),
        is_central=bool(meta.get("is_central", True)),
        gender_eligibility=str(meta.get("gender_eligibility", "All") or "All"),
        income_ceiling=str(meta.get("income_ceiling", "No Limit") or "No Limit"),
        education_level=str(meta.get("education_level", "All") or "All"),
        min_age=meta.get("min_age"),
        max_age=meta.get("max_age"),
        application_status=str(meta.get("application_status", "") or ""),
        is_expired=bool(meta.get("is_expired", False)),
        status=str(meta.get("status", "verified") or "verified"),
        summary=secs.get("summary", ""),
        default_reason=first_para,
    )


def load_schemes(docs_dir: str) -> dict[str, SchemeInfo]:
    root = Path(docs_dir)
    schemes: dict[str, SchemeInfo] = {}
    if not root.exists():
        log.warning("docs dir %s does not exist", root)
        return schemes
    for p in sorted(root.glob("*.md")):
        if p.name.lower() == "readme.md":
            continue
        m = LANG_SUFFIX.search(p.stem)
        if m and m.group(1) in KNOWN_LANGS:
            continue  # translations carry no extra metadata
        text = p.read_text(encoding="utf-8")
        fm = _FM.match(text)
        if not fm:
            continue  # no metadata -> never a recommendable scheme
        try:
            meta = yaml.safe_load(fm.group(1)) or {}
            schemes[str(meta["scheme_id"])] = _from_meta(meta, text[fm.end():])
        except (yaml.YAMLError, KeyError, TypeError) as e:
            log.error("bad front-matter in %s: %s", p.name, e)
    for d in sorted(x for x in root.iterdir() if x.is_dir()):
        mf = d / "meta.yaml"
        if mf.exists() and d.name not in schemes:
            try:
                meta = yaml.safe_load(mf.read_text(encoding="utf-8")) or {}
                meta.setdefault("scheme_id", d.name)
                schemes[str(meta["scheme_id"])] = _from_meta(meta)
            except (yaml.YAMLError, TypeError) as e:
                log.error("bad meta.yaml in %s: %s", d.name, e)
    return schemes
