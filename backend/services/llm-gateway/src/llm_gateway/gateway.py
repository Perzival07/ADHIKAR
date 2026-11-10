from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator
from typing import Any

from haqdaar_common import Registry

from .config import Settings
from .contract_models import ChatRequest, ChatResponse, ModelAliasInfo, Usage
from .errors import JsonValidationFailed, ProviderTimeout, ProviderUnavailable, QueueFull
from .jsonmode import instruction_message, repair_message, validate
from .providers import ProviderRequest, ProviderResult
from .registry import AliasEntry
from .registry import Registry as ProviderRegistry

log = logging.getLogger("llm_gateway")


class Limiter:
    """Bounded concurrency: `concurrency` running, `queue_max` waiting, otherwise QueueFull."""

    def __init__(self, concurrency: int, queue_max: int):
        self._sem = asyncio.Semaphore(max(1, concurrency))
        self._queue_max = queue_max
        self._waiting = 0

    async def __aenter__(self):
        if self._sem.locked() and self._waiting >= self._queue_max:
            raise QueueFull("LLM is busy; try again shortly")
        self._waiting += 1
        try:
            await self._sem.acquire()
        finally:
            self._waiting -= 1

    async def __aexit__(self, *exc):
        self._sem.release()


class Gateway:
    def __init__(self, registry: ProviderRegistry, settings: Settings, metrics: Registry | None = None):
        self.registry = registry
        self.settings = settings
        self.limiter = Limiter(settings.concurrency, settings.queue_max)
        m = metrics or Registry()
        self.m_requests = m.counter("llmgw_requests_total", "Chat requests", ("alias", "provider", "outcome"))
        self.m_tokens = m.counter("llmgw_tokens_total", "LLM tokens", ("alias", "kind"))
        self.m_repairs = m.counter("llmgw_json_repairs_total", "JSON repair attempts", ("alias",))
        self.m_failures = m.counter("llmgw_provider_failures_total", "Provider failures", ("alias", "provider"))
        self.m_rejected = m.counter("llmgw_queue_rejections_total", "Requests rejected because the queue was full", ())

    # ------------------------------------------------------------------ helpers
    def _build(self, entry: AliasEntry, req: ChatRequest, messages: list[dict[str, str]]) -> ProviderRequest:
        msgs = list(messages)
        schema = req.json_schema
        if schema is not None and not entry.provider.capabilities.supports_json_schema:
            msgs = [{"role": "system", "content": instruction_message(schema)}, *msgs]
        return ProviderRequest(
            model=entry.model, messages=msgs, json_schema=schema,
            max_tokens=req.max_tokens, temperature=req.temperature, options=entry.options,
        )

    def _chain(self, alias: str) -> list[AliasEntry]:
        first = self.registry.get(alias)
        return [first, *(self.registry.get(a) for a in first.fallback)]

    async def _call(self, entry: AliasEntry, req: ChatRequest, messages: list[dict[str, str]]) -> ProviderResult:
        return await entry.provider.chat(self._build(entry, req, messages))

    async def _run_chain(self, req: ChatRequest, messages: list[dict[str, str]]) -> tuple[AliasEntry, ProviderResult]:
        last: Exception | None = None
        for entry in self._chain(req.model_alias):
            try:
                return entry, await self._call(entry, req, messages)
            except (ProviderUnavailable, ProviderTimeout) as e:
                self.m_failures.inc(alias=entry.alias, provider=entry.provider_name)
                log.warning("provider failed", extra={"fields": {"alias": entry.alias, "provider": entry.provider_name, "error": e.message}})
                last = e
        assert last is not None
        raise last

    # --------------------------------------------------------------------- chat
    def _done(self, alias: str, provider: str, outcome: str, usage: Usage | None = None) -> None:
        self.m_requests.inc(alias=alias, provider=provider, outcome=outcome)
        if usage:
            self.m_tokens.inc(usage.prompt_tokens, alias=alias, kind="prompt")
            self.m_tokens.inc(usage.completion_tokens, alias=alias, kind="completion")

    async def chat(self, req: ChatRequest) -> ChatResponse:
        messages = [m.model_dump() for m in req.messages]
        try:
            async with self.limiter:
                return await self._chat_locked(req, messages)
        except QueueFull:
            self.m_rejected.inc()
            self._done(req.model_alias, "-", "queue_full")
            raise

    async def _chat_locked(self, req: ChatRequest, messages: list[dict[str, str]]) -> ChatResponse:
        try:
            entry, result = await self._run_chain(req, messages)
        except (ProviderUnavailable, ProviderTimeout):
            self._done(req.model_alias, "-", "provider_error")
            raise
        usage = Usage(prompt_tokens=result.prompt_tokens, completion_tokens=result.completion_tokens)
        if req.json_schema is None:
            self._done(req.model_alias, entry.provider_name, "ok", usage)
            return ChatResponse(text=result.text, usage=usage, provider=entry.provider_name, model=entry.model)

        obj, err = validate(result.text, req.json_schema)
        if err is not None:
            self.m_repairs.inc(alias=req.model_alias)
            # One repair attempt that includes the validation error.
            repair = [*messages, {"role": "assistant", "content": result.text}, {"role": "user", "content": repair_message(err)}]
            result2 = await self._call(entry, req, repair)
            usage = Usage(
                prompt_tokens=usage.prompt_tokens + result2.prompt_tokens,
                completion_tokens=usage.completion_tokens + result2.completion_tokens,
            )
            obj, err2 = validate(result2.text, req.json_schema)
            if err2 is not None:
                self._done(req.model_alias, entry.provider_name, "invalid_json", usage)
                raise JsonValidationFailed(err2, raw=result2.text)
            result = result2
        self._done(req.model_alias, entry.provider_name, "ok", usage)
        return ChatResponse(text=result.text, json=obj, usage=usage, provider=entry.provider_name, model=entry.model)

    # ------------------------------------------------------------------- stream
    async def stream(self, req: ChatRequest) -> AsyncIterator[dict[str, Any]]:
        """Yields {'delta': str} events then {'done': usage}. Streaming skips JSON repair."""
        messages = [m.model_dump() for m in req.messages]
        entry = self.registry.get(req.model_alias)
        async with self.limiter:
            n = 0
            async for delta in entry.provider.stream(self._build(entry, req, messages)):
                n += 1
                yield {"delta": delta}
            yield {"done": {"completion_tokens": n, "provider": entry.provider_name, "model": entry.model}}

    # ------------------------------------------------------------------- models
    def models(self) -> list[ModelAliasInfo]:
        return [
            ModelAliasInfo(
                alias=e.alias, provider=e.provider_name, model=e.model,
                supports_json_schema=e.provider.capabilities.supports_json_schema,
                supports_streaming=e.provider.capabilities.supports_streaming,
                max_context=e.provider.capabilities.max_context,
            )
            for e in self.registry.entries.values()
        ]

    async def health(self) -> dict[str, bool]:
        res = await asyncio.gather(*(e.provider.health() for e in self.registry.entries.values()), return_exceptions=True)
        return {a: (r is True) for a, r in zip(self.registry.entries, res, strict=True)}
