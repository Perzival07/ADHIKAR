"""Tiny declarative condition language for eligibility rules.

Combinators:  all: [..]   any: [..]   not: <node>
Profile ops:  eq/ne/gt/gte/lt/lte: [field, value]    in: [field, [values]]    is: <boolean field>
Scheme ops:   scheme_eq/scheme_ne: [field, value]    scheme_contains: [field, substring]   scheme_flag: <name>
Special:      same_state: true      gender_mismatch: true      age_outside_range: true
              python: <registered predicate>  (escape hatch, see predicates.py)
Every node is a mapping with exactly one key.
"""
from __future__ import annotations

import re
from typing import Any

from .predicates import PREDICATES
from .schemes import SchemeInfo


class RuleError(ValueError):
    pass


COMPARE = {"eq", "ne", "gt", "gte", "lt", "lte"}
SCHEME_FIELDS = {
    "id", "name", "category", "state_scope", "is_central", "gender_eligibility", "income_ceiling", "education_level",
    "min_age", "max_age", "application_status", "is_expired", "status", "summary", "default_reason",
}
SCHEME_FLAGS = {"is_central", "is_expired"}
OPS = COMPARE | {"in", "is", "scheme_eq", "scheme_ne", "scheme_contains", "scheme_flag", "same_state",
                 "gender_mismatch", "age_outside_range", "python", "all", "any", "not"}


def validate_condition(node: Any, profile_fields: set[str], path: str = "when") -> None:
    if not isinstance(node, dict) or len(node) != 1:
        raise RuleError(f"{path}: a condition must be a mapping with exactly one key, got {node!r}")
    (op, arg), = node.items()
    if op not in OPS:
        raise RuleError(f"{path}: unknown operator {op!r}")
    if op in {"all", "any"}:
        if not isinstance(arg, list) or not arg:
            raise RuleError(f"{path}.{op}: expects a non-empty list")
        for i, child in enumerate(arg):
            validate_condition(child, profile_fields, f"{path}.{op}[{i}]")
    elif op == "not":
        validate_condition(arg, profile_fields, f"{path}.not")
    elif op in COMPARE or op == "in":
        if not (isinstance(arg, list) and len(arg) == 2):
            raise RuleError(f"{path}.{op}: expects [field, value]")
        if arg[0] not in profile_fields:
            raise RuleError(f"{path}.{op}: unknown profile field {arg[0]!r}")
        if op == "in" and not isinstance(arg[1], list):
            raise RuleError(f"{path}.in: second item must be a list")
    elif op == "is":
        if arg not in profile_fields:
            raise RuleError(f"{path}.is: unknown profile field {arg!r}")
    elif op in {"scheme_eq", "scheme_ne", "scheme_contains"}:
        if not (isinstance(arg, list) and len(arg) == 2 and arg[0] in SCHEME_FIELDS):
            raise RuleError(f"{path}.{op}: expects [scheme_field, value] with a known scheme field")
    elif op == "scheme_flag":
        if arg not in SCHEME_FLAGS:
            raise RuleError(f"{path}.scheme_flag: unknown flag {arg!r}")
    elif op == "python":
        if arg not in PREDICATES:
            raise RuleError(f"{path}.python: predicate {arg!r} is not registered in predicates.py")
    elif arg is not True:
        raise RuleError(f"{path}.{op}: expects true")


def _cmp(op: str, a: Any, b: Any) -> bool:
    if op == "eq":
        return a == b
    if op == "ne":
        return a != b
    if op == "gt":
        return a > b
    if op == "gte":
        return a >= b
    if op == "lt":
        return a < b
    return a <= b


def evaluate(node: dict, ctx: dict[str, Any], scheme: SchemeInfo) -> bool:
    (op, arg), = node.items()
    if op == "all":
        return all(evaluate(c, ctx, scheme) for c in arg)
    if op == "any":
        return any(evaluate(c, ctx, scheme) for c in arg)
    if op == "not":
        return not evaluate(arg, ctx, scheme)
    if op in COMPARE:
        return _cmp(op, ctx[arg[0]], arg[1])
    if op == "in":
        return ctx[arg[0]] in arg[1]
    if op == "is":
        return bool(ctx[arg])
    if op == "scheme_eq":
        return getattr(scheme, arg[0]) == arg[1]
    if op == "scheme_ne":
        return getattr(scheme, arg[0]) != arg[1]
    if op == "scheme_contains":
        return str(arg[1]).lower() in scheme.text(arg[0])
    if op == "scheme_flag":
        return bool(getattr(scheme, arg))
    if op == "same_state":
        return scheme.state_scope.lower().strip() == str(ctx["state"]).lower().strip()
    if op == "gender_mismatch":
        return scheme.gender_eligibility != "All" and scheme.gender_eligibility.lower().strip() != str(ctx["gender"]).lower().strip()
    if op == "age_outside_range":
        age = ctx["age"]
        return (scheme.min_age is not None and age < scheme.min_age) or (scheme.max_age is not None and age > scheme.max_age)
    if op == "python":
        return bool(PREDICATES[arg](ctx, scheme))
    raise RuleError(f"unreachable operator {op}")


_VAR = re.compile(r"\{([A-Za-z_][A-Za-z0-9_.]*)\}")


def render(template: str, ctx: dict[str, Any], scheme: SchemeInfo) -> str:
    def sub(m: re.Match) -> str:
        key = m.group(1)
        if key.startswith("scheme."):
            return str(getattr(scheme, key[7:]))
        return str(ctx[key])

    return _VAR.sub(sub, template)


def validate_template(template: str, profile_fields: set[str], path: str) -> None:
    for key in _VAR.findall(template):
        if key.startswith("scheme."):
            if key[7:] not in SCHEME_FIELDS:
                raise RuleError(f"{path}: unknown scheme field in template {{{key}}}")
        elif key not in profile_fields:
            raise RuleError(f"{path}: unknown profile field in template {{{key}}}")
