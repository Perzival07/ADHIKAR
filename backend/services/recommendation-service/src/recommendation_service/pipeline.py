from __future__ import annotations

import json
import logging
import re
import time
from collections.abc import Awaitable, Callable
from typing import Any

from haqdaar_common import Cache, get_request_id, profile_hash, redact_profile

from . import prompts
from .clients import Clients, DependencyError
from .config import Settings
from .context import build_context, by_eligibility, escape_doc_text, group_by_scheme
from .contract_models import (
    ChatMessage,
    ChatRequest,
    ExplainRequest,
    ExplainResponse,
    Recommendation,
    RecommendationRequest,
    RecommendationResponse,
)
from .fallback import rules_only
from .llm_schema import TRANSLATE_SCHEMA, ExplainOutput, explain_schema, output_schema
from .metrics import Metrics
from .singleflight import SingleFlight
from .validate import make_citation, validate_recommendations

log = logging.getLogger("recommendation_service")
Emit = Callable[[str, dict[str, Any]], Awaitable[None]]


def parse_json_loose(text: str) -> Any:
    t = text.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", t, re.DOTALL)
    if m:
        t = m.group(1).strip()
    try:
        return json.loads(t)
    except json.JSONDecodeError:
        a, b = t.find("{"), t.rfind("}")
        if a >= 0 and b > a:
            return json.loads(t[a : b + 1])
        raise


class Pipeline:
    def __init__(self, settings: Settings, clients: Clients, cache: Cache, metrics: Metrics):
        self.s, self.clients, self.cache, self.metrics = settings, clients, cache, metrics
        self.flight: SingleFlight[RecommendationResponse] = SingleFlight()
        self.direct = {x.strip() for x in settings.direct_languages.split(",") if x.strip()}
        prompts.check_versions(settings.prompt_version, settings.explain_prompt_version)

    def generation_language(self, requested: str) -> str:
        """The language the LLM writes in: the requested one if it is a 'direct' language, else the pivot."""
        return requested if requested in self.direct else self.s.pivot_language

    async def _translate_texts(self, texts: list[str], target: str) -> list[str] | None:
        """Translate via the 'translate' alias. None on any failure (callers keep the pivot-language text)."""
        if not texts:
            return []
        chat = ChatRequest(
            model_alias=self.s.translate_alias,
            messages=[ChatMessage(role="system", content=prompts.translate_system(target)),
                      ChatMessage(role="user", content=json.dumps(texts, ensure_ascii=False))],
            json_schema=TRANSLATE_SCHEMA, max_tokens=self.s.llm_max_tokens, temperature=0.0,
        )
        try:
            resp = await self.clients.chat(chat, self.s.llm_timeout)
            out = (resp.json_ or {}).get("translations")
        except DependencyError as e:
            log.warning("translation failed: %s", e)
            self.metrics.inc("translate_failed_total")
            return None
        if not isinstance(out, list) or len(out) != len(texts) or not all(isinstance(x, str) and x.strip() for x in out):
            self.metrics.inc("translate_failed_total")
            return None
        return [x.strip() for x in out]

    async def _translate_recs(self, recs: list[Recommendation], target: str) -> list[Recommendation]:
        flat: list[str] = []
        for r in recs:
            flat.append(r.reason)
            flat.extend(r.missing_info)
        tr = await self._translate_texts(flat, target)
        if tr is None:
            return recs  # keep pivot-language text; reason_language already says which language it is
        it = iter(tr)
        out = []
        for r in recs:
            reason = next(it)
            missing = [next(it) for _ in r.missing_info]
            out.append(r.model_copy(update={"reason": reason, "missing_info": missing, "reason_language": target}))
        return out

    # ------------------------------------------------------------------ helpers
    def _cache_key(self, req: RecommendationRequest, phash: str) -> str:
        return f"{phash}|{req.language}|{self.s.prompt_version}|{self.s.llm_alias}|{req.top_n}|{req.include_citations}"

    def _response(self, recs, more, mode, trace_id, reason=None) -> RecommendationResponse:
        return RecommendationResponse(recommendations=recs, more=more, mode=mode, trace_id=trace_id, fallback_reason=reason)

    def _fallback(self, req, elig, chunks, trace_id, reason: str) -> RecommendationResponse:
        self.metrics.inc("fallback_total")
        self.metrics.inc(f"fallback_reason_{reason}")
        recs = rules_only(elig, chunks, req.include_citations)
        return self._response(recs[: req.top_n], recs[req.top_n : req.top_n + self.s.max_more], "rules_only", trace_id, reason)

    # ---------------------------------------------------------------------- run
    async def run(self, req: RecommendationRequest, emit: Emit | None = None, stream_llm: bool = False,
                  use_cache: bool = True) -> RecommendationResponse:
        trace_id = get_request_id()
        self.metrics.inc("requests_total")
        key = self._cache_key(req, profile_hash(req.profile.model_dump()))
        if use_cache:
            cached = await self.cache.get(key)
            if cached is not None:
                self.metrics.inc("cache_hit_total")
                return RecommendationResponse.model_validate_json(cached).model_copy(update={"trace_id": trace_id})
        if emit is not None:  # streaming requests are per-caller (they emit progress events)
            return await self._compute(req, key, emit, stream_llm)
        result, shared = await self.flight.do(key, lambda: self._compute(req, key, None, False))
        if shared:
            self.metrics.inc("coalesced_total")
        return result.model_copy(update={"trace_id": trace_id})

    async def _compute(self, req: RecommendationRequest, key: str, emit: Emit | None, stream_llm: bool) -> RecommendationResponse:
        t0 = time.monotonic()
        trace_id = get_request_id()
        profile = req.profile

        async def say(event: str, data: dict[str, Any]) -> None:
            if emit:
                await emit(event, data)

        # 1. deterministic eligibility (no fallback possible without it)
        t_stage = time.monotonic()
        elig_list = await self.clients.eligibility(profile)
        self.metrics.observe_stage("eligibility", time.monotonic() - t_stage)
        elig = {e.scheme_id: e for e in elig_list}
        active = [e for e in elig_list if e.status in ("eligible", "unknown")]
        await say("eligibility", {"eligible": sum(e.status == "eligible" for e in active), "unknown": sum(e.status == "unknown" for e in active)})
        if not active:
            return self._response([], [], "rules_only", trace_id, "no_eligible_schemes")

        # 2. retrieval
        t_stage = time.monotonic()
        try:
            chunks = await self.clients.search(prompts.build_query(profile), [e.scheme_id for e in active], profile.state, req.language)
            self.metrics.observe_stage("retrieval", time.monotonic() - t_stage)
        except DependencyError as e:
            log.warning("retrieval failed: %s", e)
            return self._fallback(req, elig, [], trace_id, "retrieval_unavailable")
        await say("retrieval", {"chunks": len(chunks), "schemes": len({c.scheme_id for c in chunks})})
        if not chunks:
            return self._fallback(req, elig, [], trace_id, "no_documents_retrieved")

        # 3. context + LLM
        gen_lang = self.generation_language(req.language)
        bundle = build_context(chunks, elig, self.s.context_token_budget)
        remaining = self.s.request_deadline - (time.monotonic() - t0)
        if remaining < 2.0:
            return self._fallback(req, elig, chunks, trace_id, "deadline_exceeded")

        chat = ChatRequest(
            model_alias=self.s.llm_alias,
            messages=[
                ChatMessage(role="system", content=prompts.system_prompt(self.s.prompt_version, gen_lang, req.top_n)),
                ChatMessage(role="user", content=prompts.user_prompt(
                    self.s.prompt_version, prompts.build_query(profile), bundle.candidates_text, bundle.docs_text, req.top_n)),
            ],
            json_schema=output_schema(), max_tokens=self.s.llm_max_tokens, temperature=self.s.llm_temperature,
        )
        timeout = min(self.s.llm_timeout, remaining)
        t_stage = time.monotonic()
        try:
            if stream_llm:
                text = ""
                async for delta in self.clients.chat_stream(chat, timeout):
                    text += delta
                    await say("llm_token", {"delta": delta})
                raw = parse_json_loose(text)
            else:
                resp = await self.clients.chat(chat, timeout)
                raw = resp.json_
        except DependencyError as e:
            self.metrics.inc("llm_errors_total")
            log.warning("llm failed: %s", e)
            return self._fallback(req, elig, chunks, trace_id, "llm_circuit_open" if e.circuit else f"llm_{e.status or 'unavailable'}")
        except (json.JSONDecodeError, ValueError):
            self.metrics.inc("llm_errors_total")
            return self._fallback(req, elig, chunks, trace_id, "llm_output_invalid")

        self.metrics.observe_stage("llm", time.monotonic() - t_stage)

        # 4. validate + repair
        recs, report = validate_recommendations(raw, bundle, elig, gen_lang, req.include_citations)
        items = raw.get("recommendations") if isinstance(raw, dict) else None
        if isinstance(items, list):
            self.metrics.inc("llm_items_total", len(items))
            self.metrics.inc("llm_citations_total", sum(len(i.get("citations") or []) for i in items if isinstance(i, dict)))
        self.metrics.inc("hallucinated_schemes_dropped_total", report.hallucinated_schemes)
        self.metrics.inc("invalid_citations_dropped_total", report.invalid_citations)
        if report.hallucinated_schemes or report.invalid_citations:
            log.warning("llm output repaired", extra={"fields": {"hallucinated": report.hallucinated_schemes, "bad_citations": report.invalid_citations}})
        if not recs:
            return self._fallback(req, elig, chunks, trace_id, "llm_output_invalid")

        if gen_lang != req.language:
            recs = await self._translate_recs(recs, req.language)

        # 5. "more": validated overflow, then retrieved-but-omitted, then remaining eligible
        top, overflow = recs[: req.top_n], recs[req.top_n :]
        used = {r.scheme_id for r in recs}
        retrieved_ids = by_eligibility(
            [sid for sid in group_by_scheme(chunks) if sid in elig and elig[sid].status in ("eligible", "unknown")], elig)
        omitted = [sid for sid in retrieved_ids if sid not in used]
        more = list(overflow)
        more += rules_only(elig, chunks, req.include_citations, ids=omitted)
        more += rules_only(elig, chunks, req.include_citations, skip=used | set(omitted))
        more = [m.model_copy(update={"rank": len(top) + i}) for i, m in enumerate(more[: self.s.max_more], start=1)]

        out = self._response(top, more, "rag", trace_id)
        await self.cache.set(key, out.model_dump_json(), self.s.cache_ttl)
        self.metrics.inc("mode_rag_total")
        log.info("recommendation", extra={"fields": {**redact_profile(profile.model_dump()), "mode": "rag", "returned": len(top),
                                                      "more": len(more), "ms": int((time.monotonic() - t0) * 1000)}})
        return out


    # ------------------------------------------------------------------ explain
    async def explain(self, req: ExplainRequest) -> ExplainResponse:
        trace_id = get_request_id()
        profile, sid = req.profile, req.scheme_id
        self.metrics.inc("explain_requests_total")
        elig_list = await self.clients.eligibility(profile, [sid])
        e = elig_list[0]
        try:
            chunks = await self.clients.search(
                prompts.build_query(profile) + " documents required, how to apply", [sid], profile.state, req.language,
                top_k=8, per_scheme=8)
        except DependencyError as err:
            log.warning("retrieval failed for explain: %s", err)
            return self._explain_fallback(req, e, [], trace_id, "retrieval_unavailable")
        if not chunks:
            raise LookupError(f"no documents found for scheme {sid!r}")

        name = next((c.meta.name for c in chunks if c.meta and c.meta.name), sid)
        bundle = build_context(chunks, {sid: e}, self.s.context_token_budget)
        gen_lang = self.generation_language(req.language)
        docs = "\n".join(
            f'<doc id="{c.chunk_id}" scheme="{sid}"{" flagged=" + chr(34) + "true" + chr(34) if c.flagged else ""}>\n{escape_doc_text(c.text)}\n</doc>'
            for cs in bundle.chunks_by_scheme.values() for c in cs
        )
        chat = ChatRequest(
            model_alias=self.s.llm_alias,
            messages=[
                ChatMessage(role="system", content=prompts.explain_system(self.s.explain_prompt_version, gen_lang)),
                ChatMessage(role="user", content=prompts.explain_user(
                    self.s.explain_prompt_version, prompts.build_query(profile), sid, name, e.status, (e.reasons or [""])[0], docs)),
            ],
            json_schema=explain_schema(), max_tokens=self.s.llm_max_tokens, temperature=self.s.llm_temperature,
        )
        try:
            resp = await self.clients.chat(chat, self.s.llm_timeout)
            out = ExplainOutput(**(resp.json_ or {}))
        except DependencyError as err:
            self.metrics.inc("llm_errors_total")
            return self._explain_fallback(req, e, chunks, trace_id, "llm_circuit_open" if err.circuit else f"llm_{err.status or 'unavailable'}")
        except (ValueError, TypeError):
            self.metrics.inc("llm_errors_total")
            return self._explain_fallback(req, e, chunks, trace_id, "llm_output_invalid")

        owned = {c.chunk_id for cs in bundle.chunks_by_scheme.values() for c in cs}
        by_id = {c.chunk_id: c for cs in bundle.chunks_by_scheme.values() for c in cs}
        cites = [make_citation(by_id[c.chunk_id]) for c in out.citations if c.chunk_id in owned]
        self.metrics.inc("invalid_citations_dropped_total", len(out.citations) - len(cites))
        explanation = out.explanation.strip()
        if not explanation:
            return self._explain_fallback(req, e, chunks, trace_id, "llm_output_invalid")
        docs_req = [d.strip() for d in out.documents_required if d.strip()][:15]
        steps = [s.strip() for s in out.how_to_apply if s.strip()][:10]
        lang = gen_lang
        if gen_lang != req.language:
            flat = [explanation, *docs_req, *steps]
            tr = await self._translate_texts(flat, req.language)
            if tr is not None:
                explanation, docs_req, steps = tr[0], tr[1 : 1 + len(docs_req)], tr[1 + len(docs_req) :]
                lang = req.language
        return ExplainResponse(
            scheme_id=sid, name=name, eligibility_status=e.status, eligibility_reason=(e.reasons or [""])[0],
            explanation=explanation, documents_required=docs_req, how_to_apply=steps, citations=cites,
            reason_language=lang, mode="rag", trace_id=trace_id,
        )

    def _explain_fallback(self, req: ExplainRequest, e, chunks, trace_id: str, reason: str) -> ExplainResponse:
        self.metrics.inc("fallback_total")
        name = next((c.meta.name for c in chunks if c.meta and c.meta.name), req.scheme_id)
        return ExplainResponse(
            scheme_id=req.scheme_id, name=name, eligibility_status=e.status, eligibility_reason=(e.reasons or [""])[0],
            explanation=(e.reasons or ["No further details are available right now."])[0],
            citations=[make_citation(chunks[0])] if chunks else [], reason_language="en",
            mode="rules_only", trace_id=trace_id, fallback_reason=reason,
        )
