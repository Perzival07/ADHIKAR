"""Generate JSON Schemas + OpenAPI 3.1 specs from contract_models.py.

    python contracts/generate.py          # write files
    python contracts/generate.py --check  # fail if files are stale
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).parent))
import contract_models as m

HERE = Path(__file__).parent
REF = "#/components/schemas/{model}"

SHARED_SCHEMAS = [m.CitizenProfile, m.SchemeDocMeta, m.Chunk, m.EligibilityResult, m.Recommendation]

# service -> (title, port, {path: {method: (summary, request_model|None, response_model)}})
SERVICES: dict[str, tuple[str, int, dict]] = {
    "llm-gateway": ("Haqdaar llm-gateway", 8001, {
        "/v1/chat": {"post": ("Provider-neutral chat/completion by model alias (SSE when stream=true)", m.ChatRequest, m.ChatResponse)},
        "/v1/models": {"get": ("List configured model aliases", None, m.ModelsResponse)},
    }),
    "embedding-service": ("Haqdaar embedding-service", 8002, {
        "/v1/embed": {"post": ("Embed texts", m.EmbedRequest, m.EmbedResponse)},
    }),
    "ingestion-service": ("Haqdaar ingestion-service", 8003, {
        "/v1/ingest": {"post": ("Start an ingestion run", m.IngestRequest, m.IngestStatus)},
        "/v1/ingest/status": {"get": ("Ingestion progress", None, m.IngestStatus)},
        "/v1/docs/{scheme_id}": {"delete": ("Remove a scheme's chunks", None, m.DeleteDocResponse)},
    }),
    "retrieval-service": ("Haqdaar retrieval-service", 8004, {
        "/v1/search": {"post": ("Filtered hybrid search", m.SearchRequest, m.SearchResponse)},
    }),
    "eligibility-service": ("Haqdaar eligibility-service", 8005, {
        "/v1/eligibility": {"post": ("Evaluate eligibility rules", m.EligibilityRequest, m.EligibilityResponse)},
    }),
    "recommendation-service": ("Haqdaar recommendation-service (public API)", 8000, {
        "/v1/recommendations": {"post": ("Recommend schemes for a profile", m.RecommendationRequest, m.RecommendationResponse)},
        "/v1/explain": {"post": ("Explain one scheme for a profile (detail screen)", m.ExplainRequest, m.ExplainResponse)},
    }),
}


def _collect(models: list[type[BaseModel]]) -> dict:
    comps: dict = {}
    for mod in models:
        schema = mod.model_json_schema(ref_template=REF, mode="serialization" if mod is m.ChatResponse else "validation")
        defs = schema.pop("$defs", {})
        comps.update(defs)
        comps[mod.__name__] = schema
    return comps


def build_openapi(name: str) -> dict:
    title, port, paths_def = SERVICES[name]
    used: list[type[BaseModel]] = [m.ErrorResponse]
    paths: dict = {
        "/health": {"get": {"summary": "Liveness", "responses": {"200": {"description": "ok"}}}},
        "/ready": {"get": {"summary": "Readiness (dependencies reachable)", "responses": {"200": {"description": "ready"}, "503": {"description": "not ready"}}}},
    }
    for path, methods in paths_def.items():
        paths[path] = {}
        for method, (summary, req, resp) in methods.items():
            op: dict = {"summary": summary, "operationId": f"{method}_{path.strip('/').replace('/', '_').replace('{', '').replace('}', '')}"}
            if "{scheme_id}" in path:
                op["parameters"] = [{"name": "scheme_id", "in": "path", "required": True, "schema": {"type": "string"}}]
            if req:
                used.append(req)
                op["requestBody"] = {"required": True, "content": {"application/json": {"schema": {"$ref": REF.format(model=req.__name__)}}}}
            used.append(resp)
            op["responses"] = {
                "200": {"description": "OK", "content": {"application/json": {"schema": {"$ref": REF.format(model=resp.__name__)}}}},
                "422": {"description": "Validation error"},
                "503": {"description": "Dependency unavailable", "content": {"application/json": {"schema": {"$ref": REF.format(model="ErrorResponse")}}}},
            }
            paths[path][method] = op
    return {
        "openapi": "3.1.0",
        "info": {"title": title, "version": "1.0.0", "description": "Contract is versioned by path prefix (/v1). Breaking changes require /v2."},
        "servers": [{"url": f"http://localhost:{port}"}],
        "paths": paths,
        "components": {"schemas": _collect(used)},
    }


def outputs() -> dict[Path, str]:
    out: dict[Path, str] = {}
    for mod in SHARED_SCHEMAS:
        schema = mod.model_json_schema()
        schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
        out[HERE / "schemas" / f"{mod.__name__}.json"] = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
    for name in SERVICES:
        out[HERE / "openapi" / f"{name}.yaml"] = yaml.safe_dump(build_openapi(name), sort_keys=False, allow_unicode=True)
    return out


if __name__ == "__main__":
    check = "--check" in sys.argv
    stale = []
    for path, text in outputs().items():
        if check:
            if not path.exists() or path.read_text() != text:
                stale.append(path.name)
        else:
            path.write_text(text)
    if check and stale:
        print("stale contract files:", ", ".join(stale))
        sys.exit(1)
    print("ok")
