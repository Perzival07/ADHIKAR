from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator

from ..errors import ProviderTimeout, ProviderUnavailable
from .base import Capabilities, LLMProvider, ProviderRequest, ProviderResult
from .schema_builder import build_instance, extract_schemes


class MockProvider(LLMProvider):
    """Deterministic offline provider. Options.mode: ok | hallucinate | invalid_json | error | timeout | slow."""

    name = "mock"

    def __init__(self, options: dict | None = None):
        self.options = options or {}
        self.capabilities = Capabilities(supports_json_schema=True, supports_streaming=True, max_context=8192)

    def _mode(self) -> str:
        return str(self.options.get("mode", "ok"))

    async def chat(self, req: ProviderRequest) -> ProviderResult:
        mode = self._mode()
        if mode == "error":
            raise ProviderUnavailable("mock provider configured to fail")
        if mode == "timeout":
            raise ProviderTimeout("mock provider configured to time out")
        if mode == "slow":
            await asyncio.sleep(float(self.options.get("delay", 0.2)))
        words = sum(len(m["content"].split()) for m in req.messages)
        if req.json_schema is not None:
            if mode == "invalid_json":
                text = "this is not json {"
            else:
                schemes = extract_schemes(req.messages)
                hints = {"schemes": schemes, "fill": ("citations",) if schemes else ()}
                inst = build_instance(req.json_schema, hints)
                if mode == "hallucinate" and isinstance(inst, dict) and isinstance(inst.get("recommendations"), list):
                    bogus = dict(inst["recommendations"][0]) if inst["recommendations"] else {}
                    bogus.update({"scheme_id": "totally_made_up_scheme", "rank": len(inst["recommendations"]) + 1})
                    if "citations" in bogus:
                        bogus["citations"] = [{"chunk_id": "not-a-real-chunk", "quote": ""}]
                    inst["recommendations"].append(bogus)
                text = json.dumps(inst, ensure_ascii=False)
        else:
            last = next((m["content"] for m in reversed(req.messages) if m["role"] == "user"), "")
            text = f"Mock response to: {last[:200]}"
        return ProviderResult(text=text, prompt_tokens=words, completion_tokens=len(text.split()))

    async def stream(self, req: ProviderRequest) -> AsyncIterator[str]:
        result = await self.chat(req)
        for i, w in enumerate(result.text.split(" ")):
            yield w if i == 0 else " " + w

    async def health(self) -> bool:
        return self._mode() != "error"
