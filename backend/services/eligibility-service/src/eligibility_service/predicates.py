"""ESCAPE HATCH for rules YAML cannot express.

A rule can use `{python: <name>}`; <name> must be registered here. Each predicate takes
(profile_ctx: dict, scheme: SchemeInfo) and returns bool. Keep this registry tiny: if a rule can be
written declaratively, it must be. Currently registered predicates: none are needed by shipped rules.
"""
from __future__ import annotations

from collections.abc import Callable
from typing import Any

from .schemes import SchemeInfo

PREDICATES: dict[str, Callable[[dict[str, Any], SchemeInfo], bool]] = {}
