"""End-to-end checks against the real docker-compose stack (mock LLM + hash embedder).

    make e2e          # builds + starts the stack, then runs this file

Skipped automatically when Docker is unavailable.
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

import httpx
import pytest

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND / "contracts"))
sys.path.insert(0, str(BACKEND))
import contract_models as m

from eval.golden import load_golden
from eval.runner import corpus_ids

BASE = os.environ.get("E2E_BASE", "http://localhost:8000")
CASES = {c.id: c for c in load_golden()}
FIVE = ["mh_woman_low_income", "up_farmer_2_acres", "wb_21f_student", "widow_62_bpl", "hindi_request_woman_mh"]


def compose(*args: str, check: bool = True, timeout: int = 900) -> subprocess.CompletedProcess:
    return subprocess.run(["docker", "compose", *args], cwd=BACKEND, capture_output=True, text=True, check=check, timeout=timeout)


def _ready() -> bool:
    try:
        return httpx.get(f"{BASE}/ready", timeout=3).status_code == 200
    except httpx.HTTPError:
        return False


@pytest.fixture(scope="session")
def stack():
    if shutil.which("docker") is None:
        pytest.skip("docker is not installed")
    if not _ready():
        r = compose("up", "-d", "--build", "--wait", check=False)
        if r.returncode != 0 or not _ready():
            pytest.skip(f"stack could not be started: {r.stderr[-300:]}")
    return BASE


def ingest() -> dict:
    r = compose("exec", "-T", "ingestion-service", "python", "-W", "ignore", "-m", "ingestion_service", "ingest")
    out = r.stdout
    start = out.index('{\n  "state"')
    return json.loads(out[start : out.index("\n}", start) + 2])


@pytest.fixture(scope="session")
def indexed(stack):
    first = ingest()
    assert first["state"] == "done" and not first["errors"]
    return first


def recommend(case_id: str | None = None, *, request_id: str | None = None, **over):
    case = CASES[case_id]
    body = {"profile": case.profile, "language": case.language, "top_n": case.top_n, "include_citations": True, **over}
    headers = {"Cache-Control": "no-cache"}
    if request_id:
        headers["X-Request-ID"] = request_id
    return httpx.post(f"{BASE}/v1/recommendations", json=body, headers=headers, timeout=60)


# ------------------------------------------------------------------ platform
def test_stack_is_ready_and_internal_services_are_not_exposed(stack):
    assert httpx.get(f"{BASE}/ready").json()["ready"] is True
    for port in (8001, 8002, 8003, 8004, 8005, 6333, 6379, 5432):
        with socket.socket() as s:
            s.settimeout(1)
            assert s.connect_ex(("127.0.0.1", port)) != 0, f"port {port} must not be published to the host"


def test_ingestion_is_idempotent(indexed):
    again = ingest()
    assert again["state"] == "done" and again["files_processed"] == 0 and again["chunks_added"] == 0 and again["chunks_deleted"] == 0
    assert again["files_unchanged"] == 626


# ------------------------------------------------------------------ recommendations
@pytest.mark.parametrize("case_id", FIVE)
def test_golden_profile_returns_valid_grounded_recommendations(indexed, case_id):
    r = recommend(case_id)
    assert r.status_code == 200, r.text
    resp = m.RecommendationResponse(**r.json())  # contract validation
    assert resp.mode == "rag" and resp.fallback_reason is None
    known = corpus_ids(BACKEND / "data" / "scheme_docs")
    case = CASES[case_id]
    assert 1 <= len(resp.recommendations) <= case.top_n
    for rec in resp.recommendations:
        assert rec.scheme_id in known, f"hallucinated scheme id {rec.scheme_id}"
        assert rec.reason.strip() and rec.citations, f"{rec.scheme_id}: reason and citations required"
        assert all(c.chunk_id and c.section for c in rec.citations)
    assert [r.rank for r in resp.recommendations] == list(range(1, len(resp.recommendations) + 1))
    returned = {x.scheme_id for x in [*resp.recommendations, *resp.more]}
    assert not (returned & set(case.must_not_include)), "forbidden schemes surfaced"
    assert set(case.must_include) <= returned, f"missing {set(case.must_include) - returned}"


def test_hindi_request_gets_hindi_documents_and_reasons(indexed):
    resp = m.RecommendationResponse(**recommend("hindi_request_woman_mh").json())
    assert {r.reason_language for r in resp.recommendations} == {"hi"}
    assert any(any("\u0900" <= ch <= "\u097f" for ch in r.name) for r in resp.recommendations)  # Devanagari scheme names


def test_explain_endpoint(indexed):
    r = httpx.post(f"{BASE}/v1/explain", json={"profile": CASES["up_farmer_2_acres"].profile, "scheme_id": "pm_kisan", "language": "en"}, timeout=60)
    assert r.status_code == 200, r.text
    d = m.ExplainResponse(**r.json())
    assert d.scheme_id == "pm_kisan" and d.eligibility_status == "eligible" and d.explanation.strip() and d.citations
    assert httpx.post(f"{BASE}/v1/explain", json={"profile": {}, "scheme_id": "no_such_scheme"}, timeout=30).status_code == 404


def test_validation_and_privacy_at_the_edge(stack):
    assert httpx.post(f"{BASE}/v1/recommendations", json={"profile": {"name": "Rajesh"}}).status_code == 422
    assert httpx.post(f"{BASE}/v1/recommendations", json={"profile": {}, "pad": "x" * 40000}).status_code == 413


# ------------------------------------------------------------------ observability
def test_request_id_is_traced_through_every_service(indexed):
    rid = f"e2e-trace-{uuid.uuid4().hex[:12]}"
    r = recommend("mh_woman_low_income", request_id=rid)
    assert r.status_code == 200 and r.headers["x-request-id"] == rid and r.json()["trace_id"] == rid
    time.sleep(1.0)
    seen = {}
    for svc in ("recommendation-service", "eligibility-service", "retrieval-service", "embedding-service", "llm-gateway"):
        logs = compose("logs", "--no-color", "--since", "5m", svc).stdout
        lines = [ln for ln in logs.splitlines() if rid in ln]
        seen[svc] = lines
        assert lines, f"request id {rid} not found in {svc} logs"
        assert any('"request_id": "' + rid + '"' in ln for ln in lines), f"{svc}: no structured log line with the request id"
    # privacy: the profile values must not appear anywhere in those logs
    for svc, lines in seen.items():
        blob = "\n".join(lines)
        for secret in ("socialCategory", "annualIncomeRange", "rationCard", "disabilityStatus"):
            assert secret not in blob, f"{svc} logged {secret}"


def test_metrics_reflect_traffic(indexed):
    def counter(name: str) -> float:
        text = httpx.get(f"{BASE}/metrics", timeout=10).text
        return sum(float(ln.split()[-1]) for ln in text.splitlines() if ln.startswith((name + " ", name + "{")))

    before = counter("reco_requests_total")
    recommend("rajasthan_any")
    recommend("kerala_general_man")
    assert counter("reco_requests_total") == before + 2
    text = httpx.get(f"{BASE}/metrics", timeout=10).text
    assert "reco_stage_seconds_count" in text and 'route="/v1/recommendations"' in text and "reco_llm_items_total" in text
    for secret in ("Antyodaya", "Divyangjan", "Rajasthan", "Kerala"):
        assert secret not in text, f"metrics leak profile data: {secret}"


# ------------------------------------------------------------------ resilience on the real network
def test_llm_container_down_falls_back_to_rules_then_recovers(indexed):
    compose("stop", "llm-gateway")
    try:
        r = recommend("odisha_woman_40")
        assert r.status_code == 200
        d = r.json()
        assert d["mode"] == "rules_only" and d["fallback_reason"] and d["fallback_reason"].startswith("llm_")
        assert d["recommendations"] and "or_subhadra" in {x["scheme_id"] for x in d["recommendations"] + d["more"]}
        assert httpx.get(f"{BASE}/ready").json()["checks"]["llm-gateway"] is False
    finally:
        compose("start", "llm-gateway")
    for _ in range(40):
        if httpx.get(f"{BASE}/ready").json()["checks"]["llm-gateway"]:
            break
        time.sleep(1)
    assert recommend("odisha_woman_40").json()["mode"] == "rag"


# ------------------------------------------------------------------ accounts end to end
AUTH = os.environ.get("E2E_AUTH", "http://localhost:8006")


def _otp_from_logs(email_masked: str, since: str = "2m") -> str:
    import re

    for _ in range(20):
        logs = compose("logs", "--no-color", "--since", since, "auth-service").stdout
        codes = re.findall(r"OTP for " + re.escape(email_masked) + r" \(signup\): (\d{6})", logs)
        if codes:
            return codes[-1]
        time.sleep(0.5)
    raise AssertionError("OTP not found in auth-service logs")


def test_signup_login_and_authenticated_recommendations(stack):
    email = f"e2e-{uuid.uuid4().hex[:8]}@example.com"
    assert httpx.post(f"{AUTH}/v1/auth/otp/request", json={"email": email, "purpose": "signup"}).status_code == 202
    code = _otp_from_logs(email[0] + "***@example.com")
    r = httpx.post(f"{AUTH}/v1/auth/signup", json={"email": email, "code": code, "password": "e2e-pass-123", "name": "E2E",
                                                   "state": "Odisha"})
    assert r.status_code == 201, r.text
    tokens = r.json()
    me = httpx.get(f"{AUTH}/v1/users/me", headers={"Authorization": f"Bearer {tokens['access_token']}"}).json()
    assert me["email"] == email and me["state"] == "Odisha"

    # the recommendation API verifies the token through auth-service's JWKS (no shared secret)
    ok = httpx.post(f"{BASE}/v1/recommendations", json={"profile": {"state": "Odisha"}},
                    headers={"Authorization": f"Bearer {tokens['access_token']}"}, timeout=60)
    assert ok.status_code == 200
    bad = httpx.post(f"{BASE}/v1/recommendations", json={"profile": {}}, headers={"Authorization": "Bearer forged.token.x"})
    assert bad.status_code == 401

    # refresh rotation + logout across the real database
    r2 = httpx.post(f"{AUTH}/v1/auth/token/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r2.status_code == 200
    assert httpx.post(f"{AUTH}/v1/auth/token/refresh", json={"refresh_token": tokens["refresh_token"]}).status_code == 401
    assert httpx.post(f"{AUTH}/v1/auth/login", json={"identifier": email, "password": "e2e-pass-123"}).status_code == 200


def test_demo_accounts_seeded_in_development(stack):
    r = httpx.post(f"{AUTH}/v1/auth/login", json={"identifier": "citizen@adhikar.gov.in", "password": "password123"})
    assert r.status_code == 200 and r.json()["user"]["name"] == "Rajesh Sharma"
