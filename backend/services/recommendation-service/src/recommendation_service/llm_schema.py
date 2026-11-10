"""Schema we ask the LLM to follow. Deliberately lenient (no min/max): we clamp and validate ourselves."""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class LLMCitation(BaseModel):
    chunk_id: str
    quote: str = ""


class LLMRecommendation(BaseModel):
    scheme_id: str
    rank: int
    confidence: float
    reason: str
    citations: list[LLMCitation] = []
    missing_info: list[str] = []


class LLMOutput(BaseModel):
    recommendations: list[LLMRecommendation]


class ExplainOutput(BaseModel):
    explanation: str
    documents_required: list[str] = []
    how_to_apply: list[str] = []
    citations: list[LLMCitation] = []


def output_schema() -> dict[str, Any]:
    return LLMOutput.model_json_schema()


def explain_schema() -> dict[str, Any]:
    return ExplainOutput.model_json_schema()


TRANSLATE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {"translations": {"type": "array", "items": {"type": "string"}}},
    "required": ["translations"],
}
