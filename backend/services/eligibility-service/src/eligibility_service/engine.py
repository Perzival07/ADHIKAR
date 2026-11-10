from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from .contract_models import CitizenProfile, EligibilityResult
from .dsl import RuleError, evaluate, render, validate_condition, validate_template
from .profile_ctx import build_context
from .schemes import SchemeInfo

RULES_DIR = Path(__file__).parent / "rules"
PROFILE_FIELDS = set(build_context(CitizenProfile()))
THRESHOLD = 0.5  # score >= 0.5 <=> eligible (same as the Flutter engine)


@dataclass
class Outcome:
    status: str
    score: float
    reason: str
    when: dict | None = None
    missing_fields: tuple[str, ...] = ()
    id: str = ""


DEFAULT_OUTCOME = Outcome("ineligible", 0.0, "You do not meet the eligibility criteria for this scheme.")


def _parse_outcome(raw: dict, where: str) -> Outcome:
    if "when" in raw:
        validate_condition(raw["when"], PROFILE_FIELDS, f"{where}.when")
    validate_template(raw["reason"], PROFILE_FIELDS, f"{where}.reason")
    status, score = raw["status"], float(raw["score"])
    if (status == "eligible") != (score >= THRESHOLD):
        raise RuleError(f"{where}: status {status!r} is inconsistent with score {score} (eligible <=> score >= {THRESHOLD})")
    return Outcome(status, score, raw["reason"], raw.get("when"), tuple(raw.get("missing_fields", ())), raw.get("id", ""))


class Rules:
    def __init__(self, specific: dict[str, tuple[list[Outcome], Outcome]], generic: list[Outcome]):
        self.specific = specific
        self.generic = generic

    @classmethod
    def load(cls, rules_dir: Path = RULES_DIR) -> Rules:
        schema = json.loads((rules_dir / "rules.schema.json").read_text())
        specific: dict[str, tuple[list[Outcome], Outcome]] = {}
        generic: list[Outcome] = []
        for f in sorted(rules_dir.glob("*.yaml")):
            data = yaml.safe_load(f.read_text(encoding="utf-8"))
            try:
                jsonschema.validate(data, schema)
            except jsonschema.ValidationError as e:
                raise RuleError(f"{f.name}: {e.message} at {'/'.join(map(str, e.absolute_path))}") from e
            if "schemes" in data:
                for sid, spec in data["schemes"].items():
                    if sid in specific:
                        raise RuleError(f"{f.name}: duplicate rule for scheme {sid!r}")
                    outs = [_parse_outcome(o, f"{f.name}:{sid}[{i}]") for i, o in enumerate(spec["outcomes"])]
                    default = _parse_outcome(spec["default"], f"{f.name}:{sid}.default") if "default" in spec else DEFAULT_OUTCOME
                    specific[sid] = (outs, default)
            else:
                for i, r in enumerate(data["rules"]):
                    generic.append(_parse_outcome(r, f"{f.name}:{r['id']}"))
                    if "when" not in r and i != len(data["rules"]) - 1:
                        raise RuleError(f"{f.name}:{r['id']}: only the last generic rule may omit `when`")
        if not generic or generic[-1].when is not None:
            raise RuleError("generic.yaml must end with an unconditional fallback rule")
        return cls(specific, generic)


class Engine:
    def __init__(self, schemes: dict[str, SchemeInfo], rules: Rules):
        self.schemes = schemes
        self.rules = rules

    def _decide(self, ctx: dict[str, Any], scheme: SchemeInfo) -> Outcome:
        if scheme.status != "verified":
            return Outcome("ineligible", 0.0, "This scheme has no verified metadata yet.")
        if not str(ctx["state"]).strip() and not scheme.is_central and scheme.state_scope != "All":
            return Outcome("unknown", 0.0, "Your state is needed to check this state scheme.", missing_fields=("state",))
        if scheme.id in self.rules.specific:
            outs, default = self.rules.specific[scheme.id]
            for o in outs:
                if evaluate(o.when, ctx, scheme):
                    return o
            return default
        for o in self.rules.generic:
            if o.when is None or evaluate(o.when, ctx, scheme):
                return o
        return DEFAULT_OUTCOME  # unreachable: generic ends with a fallback

    def evaluate(self, profile: CitizenProfile, scheme_ids: list[str] | None = None) -> list[EligibilityResult]:
        ctx = build_context(profile)
        ids = scheme_ids if scheme_ids is not None else list(self.schemes)
        out = []
        for sid in ids:
            scheme = self.schemes.get(sid)
            if scheme is None:
                out.append(EligibilityResult(scheme_id=sid, status="ineligible", reasons=["Unknown scheme."]))
                continue
            o = self._decide(ctx, scheme)
            out.append(EligibilityResult(
                scheme_id=sid, status=o.status, score=o.score,  # type: ignore[arg-type]
                reasons=[render(o.reason, ctx, scheme)], missing_fields=list(o.missing_fields),
            ))
        return out
