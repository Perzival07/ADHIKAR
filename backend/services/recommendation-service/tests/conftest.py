import json
import re

import httpx
import pytest

from recommendation_service.config import Settings
from recommendation_service.main import create_app

DOC = re.compile(r'<doc id="([^"]+)" scheme="([^"]+)"')


def meta(sid, name=None, lang="en"):
    return {"scheme_id": sid, "name": name or sid.replace("_", " ").title(), "state_scope": "All", "is_central": True, "category": "x",
            "gender_eligibility": "All", "income_ceiling": "No Limit", "min_age": None, "max_age": None, "education_level": "All",
            "official_portal_url": "https://x", "last_verified_date": "", "language": lang, "source_type": "corpus", "status": "verified"}


def chunk(cid, sid, text="Scheme text.", flagged=False, name=None):
    return {"chunk_id": cid, "scheme_id": sid, "text": text, "section": "Benefit", "page": None, "source": f"{sid}.md",
            "meta": meta(sid, name), "score": 0.5, "flagged": flagged}


def elig(sid, status="eligible", score=1.0, reason=None, missing=()):
    return {"scheme_id": sid, "status": status, "score": score, "reasons": [reason or f"Rule reason for {sid}."], "missing_fields": list(missing)}


class FakeStack:
    """Routes httpx requests to fake eligibility / retrieval / llm-gateway services by port."""

    def __init__(self):
        self.elig = [elig("pm_kisan"), elig("ayushman", score=0.85), elig("sukanya", status="unknown", score=0.4, missing=["landHoldingAcres"]),
                     elig("not_for_you", status="ineligible", score=0.0)]
        self.chunks = [chunk("c_kisan_1", "pm_kisan", "PM-KISAN gives 6000 rupees per year."), chunk("c_kisan_2", "pm_kisan", "Apply at CSC."),
                       chunk("c_ayush_1", "ayushman", "Health cover of 5 lakh."), chunk("c_suk_1", "sukanya", "Savings for girl child.")]
        self.llm_mode = "ok"
        self.translate_mode = "ok"  # ok | fail | short
        self.explain_mode = "ok"  # ok | bad_cites | empty | invalid
        self.llm_calls: list[dict] = []
        self.retrieval_calls: list[dict] = []
        self.elig_calls: list[dict] = []
        self.elig_down = self.retrieval_down = False

    # ---- llm behaviours
    def _recs_from_prompt(self, body):
        user = next(m["content"] for m in body["messages"] if m["role"] == "user")
        seen, recs = [], []
        for cid, sid in DOC.findall(user):
            if sid not in seen:
                seen.append(sid)
                recs.append({"scheme_id": sid, "rank": len(recs) + 1, "confidence": 0.9 - 0.1 * len(recs), "reason": f"Because of {sid}.",
                             "citations": [{"chunk_id": cid, "quote": ""}], "missing_info": []})
        return recs

    def _llm_json(self, body):
        recs = self._recs_from_prompt(body)
        m = self.llm_mode
        if m == "hallucinate":
            recs.append({"scheme_id": "made_up_scheme", "rank": 9, "confidence": 1.0, "reason": "invented", "citations": [{"chunk_id": "nope", "quote": ""}]})
        elif m == "bad_citations":
            for r in recs:
                r["citations"] = [{"chunk_id": "does-not-exist", "quote": ""}, {"chunk_id": "c_ayush_1" if r["scheme_id"] != "ayushman" else "c_kisan_1", "quote": ""}] + r["citations"]
        elif m == "ineligible_scheme":
            recs.insert(0, {"scheme_id": "not_for_you", "rank": 0, "confidence": 1, "reason": "x", "citations": []})
        elif m == "unknown_first":
            recs.sort(key=lambda r: r["scheme_id"] != "sukanya")
            for i, r in enumerate(recs, 1):
                r["rank"] = i
        elif m == "dupes":
            recs.append(dict(recs[0], rank=5))
        elif m == "wild_values":
            for r in recs:
                r["confidence"] = 7.5
                r["reason"] = "   "
        elif m == "empty":
            recs = []
        elif m == "only_first":
            recs = recs[:1]
        elif m == "quote":
            recs[0]["citations"][0]["quote"] = "6000 rupees per year"
        return {"recommendations": recs}

    def __call__(self, request: httpx.Request) -> httpx.Response:
        port = request.url.port
        body = json.loads(request.content) if request.content else {}
        if request.url.path == "/ready":
            return httpx.Response(200, json={"ready": True})
        if port == 8005:
            self.elig_calls.append(body)
            return httpx.Response(503, json={"detail": "down"}) if self.elig_down else httpx.Response(200, json={"results": self.elig})
        if port == 8004:
            self.retrieval_calls.append(body)
            if self.retrieval_down:
                raise httpx.ConnectError("down", request=request)
            allowed = set(body["filters"]["scheme_ids"] or [])
            return httpx.Response(200, json={"chunks": [c for c in self.chunks if c["scheme_id"] in allowed]})
        if port == 8001:
            self.llm_calls.append(body)
            if body.get("model_alias") == "translate":
                if self.translate_mode == "fail":
                    return httpx.Response(503, json={"detail": "translator down"})
                items = json.loads(next(m["content"] for m in body["messages"] if m["role"] == "user"))
                out = [f"[TR] {t}" for t in items]
                if self.translate_mode == "short":
                    out = out[:-1]
                return httpx.Response(200, json={"text": "", "json": {"translations": out}, "usage": {}, "provider": "mock", "model": "m"})
            if "explanation" in (body.get("json_schema") or {}).get("properties", {}):
                user = next(m["content"] for m in body["messages"] if m["role"] == "user")
                ids = [cid for cid, _ in DOC.findall(user)]
                if self.explain_mode == "invalid":
                    return httpx.Response(200, json={"text": "", "json": {"nope": 1}, "usage": {}, "provider": "mock", "model": "m"})
                exp = {"explanation": "  " if self.explain_mode == "empty" else "It gives income support to farmer families.",
                       "documents_required": ["Aadhaar", " ", "Land record"], "how_to_apply": ["Visit CSC", "Submit documents"],
                       "citations": [{"chunk_id": ids[0], "quote": ""}] + ([{"chunk_id": "forged", "quote": ""}] if self.explain_mode == "bad_cites" else [])}
                return httpx.Response(200, json={"text": "", "json": exp, "usage": {}, "provider": "mock", "model": "m"})
            if self.llm_mode == "http503":
                return httpx.Response(503, json={"detail": "LLM busy"})
            if self.llm_mode == "http429":
                return httpx.Response(429, json={"detail": "busy"})
            if self.llm_mode == "timeout":
                raise httpx.ReadTimeout("slow", request=request)
            if self.llm_mode == "422":
                return httpx.Response(422, json={"detail": "bad json", "raw": "x"})
            if body.get("stream"):
                text = "this is not json" if self.llm_mode == "invalid_json" else json.dumps(self._llm_json(body))
                parts = [text[i : i + 40] for i in range(0, len(text), 40)]
                sse = "".join(f"data: {json.dumps({'delta': p})}\n\n" for p in parts) + 'event: done\ndata: {"completion_tokens": 1}\n\n'
                return httpx.Response(200, content=sse.encode(), headers={"content-type": "text/event-stream"})
            if self.llm_mode == "invalid_json":
                return httpx.Response(200, json={"text": "nope", "json": None, "usage": {}, "provider": "mock", "model": "m"})
            return httpx.Response(200, json={"text": "", "json": self._llm_json(body), "usage": {}, "provider": "mock", "model": "m"})
        return httpx.Response(404)


@pytest.fixture
def stack():
    return FakeStack()


@pytest.fixture
def make_app(stack):
    def _make(**kw):
        s = Settings(eligibility_url="http://elig:8005", retrieval_url="http://ret:8004", llm_gateway_url="http://llm:8001", **kw)
        return create_app(s, transport=httpx.MockTransport(stack))

    return _make


PROFILE = {"state": "Uttar Pradesh", "age": 35, "gender": "Female", "occupation": "Farmer", "landHoldingAcres": 2.0,
           "socialCategory": "OBC", "rationCard": "Antyodaya (AAY)", "annualIncomeRange": "< 1 Lakh", "disabilityStatus": "40%+ (Divyangjan)"}
