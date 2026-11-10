from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

GOLDEN_DIR = Path(__file__).parent / "golden"
ALLOWED = {"id", "notes", "language", "top_n", "profile", "must_include", "must_not_include", "expect"}


@dataclass
class Case:
    id: str
    profile: dict[str, Any]
    language: str = "en"
    top_n: int = 8
    must_include: list[str] = field(default_factory=list)
    must_not_include: list[str] = field(default_factory=list)
    expect: dict[str, Any] = field(default_factory=dict)
    notes: str = ""


class GoldenError(ValueError):
    pass


def load_golden(directory: Path = GOLDEN_DIR) -> list[Case]:
    cases: list[Case] = []
    seen: set[str] = set()
    for f in sorted(directory.glob("*.yaml")):
        data = yaml.safe_load(f.read_text(encoding="utf-8")) or []
        if not isinstance(data, list):
            raise GoldenError(f"{f.name}: expected a list of cases")
        for raw in data:
            unknown = set(raw) - ALLOWED
            if unknown:
                raise GoldenError(f"{f.name}:{raw.get('id')}: unknown keys {sorted(unknown)}")
            if "id" not in raw or "profile" not in raw:
                raise GoldenError(f"{f.name}: every case needs `id` and `profile`")
            if raw["id"] in seen:
                raise GoldenError(f"duplicate case id {raw['id']!r}")
            seen.add(raw["id"])
            both = set(raw.get("must_include", [])) & set(raw.get("must_not_include", []))
            if both:
                raise GoldenError(f"{raw['id']}: {sorted(both)} are both required and forbidden")
            cases.append(Case(
                id=raw["id"], profile=raw["profile"], language=raw.get("language", "en"), top_n=raw.get("top_n", 8),
                must_include=list(raw.get("must_include", [])), must_not_include=list(raw.get("must_not_include", [])),
                expect=dict(raw.get("expect", {})), notes=raw.get("notes", ""),
            ))
    return cases
