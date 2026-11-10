"""Versioned prompt + query templates live in prompts/ (files), never inline in code."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from .contract_models import CitizenProfile

PROMPTS_DIR = Path(__file__).parent / "prompts"


class PromptError(RuntimeError):
    pass


@lru_cache(maxsize=64)
def _read(name: str) -> str:
    p = PROMPTS_DIR / name
    if not p.exists():
        raise PromptError(f"prompt file not found: {name}")
    return p.read_text(encoding="utf-8").strip()


@lru_cache(maxsize=4)
def _yaml(name: str) -> dict[str, Any]:
    return yaml.safe_load(_read(name)) or {}


def language_name(code: str) -> str:
    return str(_yaml("languages.yaml").get(code, code))


def available_versions() -> list[str]:
    return sorted({p.name.split(".")[1] for p in PROMPTS_DIR.glob("recommend.*.system.md")})


def has_prompt(name: str) -> bool:
    return (PROMPTS_DIR / name).exists()


def check_versions(recommend: str, explain: str) -> None:
    """Fail fast at startup if a configured prompt version has no files."""
    needed = [f"recommend.{recommend}.system.md", f"recommend.{recommend}.user.md",
              f"explain.{explain}.system.md", f"explain.{explain}.user.md", "translate.v1.system.md"]
    missing = [n for n in needed if not has_prompt(n)]
    if missing:
        raise PromptError(f"missing prompt files: {missing}; available recommend versions: {available_versions()}")


def system_prompt(version: str, language: str, top_n: int) -> str:
    return _read(f"recommend.{version}.system.md").format(language_name=language_name(language), top_n=top_n)


def user_prompt(version: str, profile_text: str, candidates: str, docs: str, top_n: int) -> str:
    return _read(f"recommend.{version}.user.md").format(profile_text=profile_text, candidates=candidates, docs=docs, top_n=top_n)


def explain_system(version: str, language: str) -> str:
    return _read(f"explain.{version}.system.md").format(language_name=language_name(language))


def explain_user(version: str, profile_text: str, scheme_id: str, name: str, status: str, rule_reason: str, docs: str) -> str:
    return _read(f"explain.{version}.user.md").format(
        profile_text=profile_text, scheme_id=scheme_id, name=name, status=status, rule_reason=rule_reason, docs=docs)


def translate_system(language: str) -> str:
    return _read("translate.v1.system.md").format(language_name=language_name(language))


def _flags(p: CitizenProfile) -> list[str]:
    flags = []
    if p.hasGirlChildUnder10:
        flags.append("girl_child")
    if p.gender == "Female" and p.maritalStatus == "Widow":
        flags.append("widow")
    if p.disabilityStatus != "None":
        flags.append("disability")
    if p.age >= 60:
        flags.append("senior")
    if p.annualIncomeRange in ("< 1 Lakh", "1 - 2.5 Lakh") or p.rationCard in ("Antyodaya (AAY)", "BPL", "Priority (PHH)"):
        flags.append("low_income")
    if p.gender == "Female":
        flags.append("female")
    if p.socialCategory in ("SC", "ST"):
        flags.append("sc_st")
    return flags


def build_query(p: CitizenProfile) -> str:
    cfg = _yaml("intent_keywords.yaml")
    flags = _flags(p)
    kws: list[str] = list(cfg.get("default", []))
    kws += cfg.get("occupation", {}).get(p.occupation, cfg.get("occupation", {}).get("Citizen", []))
    for f in flags:
        kws += cfg.get("flags", {}).get(f, [])
    kws = list(dict.fromkeys(kws))
    flag_text = []
    if "girl_child" in flags:
        flag_text.append("Has a girl child under 10.")
    if "widow" in flags:
        flag_text.append("Widow.")
    if "disability" in flags:
        flag_text.append(f"Disability: {p.disabilityStatus}.")
    if p.occupation == "Farmer":
        flag_text.append(f"Owns {p.landHoldingAcres} acres of land.")
    if p.occupation.startswith("Artisan") and p.artisanTrade:
        flag_text.append(f"Trade: {p.artisanTrade}.")
    if p.studentLevel != "None":
        flag_text.append(f"Studying: {p.studentLevel}.")
    return _read("query.v1.md").format(
        age=p.age, gender_word={"Female": "woman", "Male": "man"}.get(p.gender, "person"),
        occupation_text=p.occupation.lower(), state=p.state, social_category=p.socialCategory,
        income=p.annualIncomeRange, ration=p.rationCard,
        flags_text=(" ".join(flag_text) + " ") if flag_text else "", keywords=", ".join(kws),
    )
