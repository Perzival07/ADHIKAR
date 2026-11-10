"""Build a minimal valid JSON instance from a JSON Schema (used by the mock provider)."""
from __future__ import annotations

import re
from typing import Any


def _resolve(node: dict, root: dict) -> dict:
    seen = 0
    while "$ref" in node and seen < 20:
        ref = node["$ref"]
        target: Any = root
        for part in ref.lstrip("#/").split("/"):
            target = target[part]
        node = target
        seen += 1
    return node


def build_instance(schema: dict, hints: dict[str, Any] | None = None, root: dict | None = None, name: str = "") -> Any:
    hints = hints or {}
    root = root or schema
    node = _resolve(schema, root)
    if "const" in node:
        return node["const"]
    if "enum" in node:
        return node["enum"][0]
    for key in ("anyOf", "oneOf"):
        if key in node:
            options = [o for o in node[key] if o.get("type") != "null"]
            return build_instance(options[0] if options else node[key][0], hints, root, name)
    if "allOf" in node:
        return build_instance(node["allOf"][0], hints, root, name)
    t = node.get("type")
    if isinstance(t, list):
        t = next((x for x in t if x != "null"), t[0])
    if t == "object" or "properties" in node:
        out = {}
        props = node.get("properties", {})
        required = set(node.get("required", []))
        for k, v in props.items():
            if k in required or k in hints.get("fill", ()):
                out[k] = build_instance(v, hints, root, k)
        return out
    if t == "array":
        item = node.get("items", {})
        if name == "recommendations" and hints.get("schemes"):
            return [_recommendation(item, hints, root, i, s) for i, s in enumerate(hints["schemes"])]
        if name == "citations" and hints.get("schemes"):
            cite = build_instance(item, hints, root, name)
            if isinstance(cite, dict):
                cite["chunk_id"] = hints["schemes"][0]["chunk_ids"][0]
            return [cite]
        n = max(node.get("minItems", 0), 0)
        return [build_instance(item, hints, root, name) for _ in range(n)]
    if t == "integer":
        lo = node.get("minimum", 0)
        if "exclusiveMinimum" in node:
            lo = max(lo, node["exclusiveMinimum"] + 1)
        return int(lo)
    if t == "number":
        return float(node.get("minimum", 0))
    if t == "boolean":
        return False
    if t == "string":
        s = hints.get("string", "mock")
        return s.ljust(node.get("minLength", 0), "x")
    if t == "null":
        return None
    return None


def _recommendation(item: dict, hints: dict, root: dict, idx: int, scheme: dict) -> Any:
    inst = build_instance(item, {**hints, "fill": ("scheme_id", "rank", "confidence", "reason", "citations")}, root)
    if isinstance(inst, dict):
        if "scheme_id" in inst:
            inst["scheme_id"] = scheme["scheme_id"]
        if "rank" in inst:
            inst["rank"] = idx + 1
        if "confidence" in inst:
            inst["confidence"] = round(max(0.5, 0.95 - idx * 0.05), 2)
        if "reason" in inst:
            inst["reason"] = f"Mock reason for {scheme['scheme_id']}."
        if "citations" in inst and scheme.get("chunk_ids"):
            inst["citations"] = [{"chunk_id": scheme["chunk_ids"][0], "quote": ""}]
    return inst


_DOC = re.compile(r'<doc\s+id="([^"]+)"\s+scheme="([^"]+)"')


def extract_schemes(messages: list[dict[str, str]]) -> list[dict[str, Any]]:
    """Find <doc id=... scheme=...> wrappers in the prompt; return schemes in order of appearance."""
    order: list[str] = []
    chunks: dict[str, list[str]] = {}
    for m in messages:
        if m.get("role") == "system":  # prompts may mention the <doc> format as an example; only real documents count
            continue
        for cid, sid in _DOC.findall(m.get("content", "")):
            if sid not in chunks:
                order.append(sid)
                chunks[sid] = []
            chunks[sid].append(cid)
    return [{"scheme_id": s, "chunk_ids": chunks[s]} for s in order]
