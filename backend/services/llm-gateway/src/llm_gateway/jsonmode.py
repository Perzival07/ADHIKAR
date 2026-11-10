from __future__ import annotations

import json
import re
from typing import Any

import jsonschema


def parse_json(text: str) -> Any:
    """Parse JSON, tolerating code fences and leading/trailing prose."""
    t = text.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", t, re.DOTALL)
    if m:
        t = m.group(1).strip()
    try:
        return json.loads(t)
    except json.JSONDecodeError:
        start = min((i for i in (t.find("{"), t.find("[")) if i >= 0), default=-1)
        end = max(t.rfind("}"), t.rfind("]"))
        if start >= 0 and end > start:
            return json.loads(t[start : end + 1])
        raise


def validate(text: str, schema: dict) -> tuple[Any | None, str | None]:
    """Return (parsed, None) if text is valid JSON for schema, else (None, error message)."""
    try:
        obj = parse_json(text)
    except (json.JSONDecodeError, ValueError) as e:
        return None, f"output is not valid JSON: {e}"
    try:
        jsonschema.validate(obj, schema)
    except jsonschema.ValidationError as e:
        path = "/".join(str(p) for p in e.absolute_path) or "(root)"
        return None, f"JSON does not match schema at {path}: {e.message}"
    except jsonschema.SchemaError as e:
        return None, f"invalid json_schema: {e.message}"
    return obj, None


def instruction_message(schema: dict) -> str:
    return (
        "Respond with ONLY a single JSON value that validates against this JSON Schema. "
        "No prose, no code fences.\n" + json.dumps(schema, ensure_ascii=False)
    )


def repair_message(error: str) -> str:
    return (
        f"Your previous reply was rejected: {error}\n"
        "Reply again with ONLY corrected JSON that satisfies the schema. No explanation."
    )
