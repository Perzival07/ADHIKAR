import json

import httpx
import pytest

from eval import __main__ as cli
from eval import report, runner
from eval.golden import Case
from eval.metrics import (
    CaseResult,
    aggregate,
    parse_prometheus,
    percentile,
    recall_at_k,
)


# ------------------------------------------------------------------ metrics
def test_recall_at_k():
    assert recall_at_k(["a", "b", "c"], ["a", "c"], 2) == 0.5
    assert recall_at_k(["a", "b", "c"], ["a", "c"], 3) == 1.0
    assert recall_at_k(["a"], [], 5) is None
    assert recall_at_k([], ["a"], 5) == 0.0


def test_percentile_nearest_rank():
    xs = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    assert percentile(xs, 50) == 50 and percentile(xs, 95) == 100 and percentile(xs, 100) == 100
    assert percentile([], 50) is None and percentile([7], 95) == 7


def _case(**kw):
    base = {"id": "x", "language": "en", "status": 200, "mode": "rag", "latency_ms": 100.0, "returned_ids": ["a"], "rec_count": 2,
            "rec_with_citation": 2, "recall5": 1.0, "recall10": 1.0}
    base.update(kw)
    return CaseResult(**base)


def test_aggregate_values():
    cases = [
        _case(latency_ms=100, recall5=1.0, recall10=1.0),
        _case(id="y", latency_ms=300, recall5=0.5, recall10=1.0, violations=["bad"], forbidden_count=1, rec_with_citation=1),
        _case(id="z", mode="rules_only", fallback_reason="llm_output_invalid", recall5=0.0, recall10=0.5, unknown_ids=["ghost"]),
        _case(id="e", status=503, recall5=None, recall10=None),
    ]
    m = aggregate(cases)
    assert m["cases"] == 4
    assert m["recall@5"] == pytest.approx(0.5) and m["recall@10"] == pytest.approx(5 / 6)
    assert m["violation_rate"] == 1.0  # only case "y" has a forbidden list, and it violated it
    assert m["unknown_id_rate"] == pytest.approx(1 / 3)
    assert m["fallback_rate"] == pytest.approx(1 / 3)
    assert m["json_valid_rate"] == pytest.approx(2 / 3)
    assert m["error_rate"] == 0.25
    assert m["citation_coverage"] == pytest.approx(3 / 4)  # rag-mode recs only: (2+1)/(2+2)
    assert m["latency_p50_ms"] == 100 and m["latency_p95_ms"] == 300
    assert m["model_hallucination_rate"] is None


def test_aggregate_model_level_rates_from_server_counters():
    m = aggregate([_case()], {"llm_items_total": 40, "hallucinated_schemes_dropped_total": 6, "llm_citations_total": 50, "invalid_citations_dropped_total": 5})
    assert m["model_hallucination_rate"] == 0.15 and m["model_citation_drop_rate"] == 0.1


def test_parse_prometheus():
    text = '# HELP x\n# TYPE x counter\nllm_items_total 12\nfoo{a="1"} 2\nfoo{a="2"} 3.5\nbad line here\n'
    assert parse_prometheus(text) == {"llm_items_total": 12.0, "foo": 5.5}
    assert parse_prometheus('{"detail":"Not Found"}') == {}


# ------------------------------------------------------------------ runner against a fake server
class FakeServer:
    def __init__(self, metrics=True):
        self.requests = []
        self.metrics_on = metrics
        self.items = 0
        self.mode = "rag"
        self.fail_for: set[str] = set()
        self.lang_override: str | None = None

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == "/metrics":
            if not self.metrics_on:
                return httpx.Response(404, json={"detail": "Not Found"})
            return httpx.Response(200, text=f"llm_items_total {self.items}\nhallucinated_schemes_dropped_total {self.items // 10}\n"
                                            f"llm_citations_total {self.items * 2}\ninvalid_citations_dropped_total 0\n")
        body = json.loads(request.content)
        self.requests.append((body, dict(request.headers)))
        state = body["profile"].get("state", "")
        if state in self.fail_for:
            return httpx.Response(503, json={"detail": "down"})
        self.items += 10
        ids = ["pm_kisan", "ayushman_bharat", "ghost_scheme"] if state == "Uttar Pradesh" else ["ayushman_bharat"]
        recs = [{"scheme_id": i, "rank": n, "confidence": 0.9, "reason": "r", "reason_language": self.lang_override or body["language"],
                 "citations": [{"chunk_id": "c"}] if i != "ayushman_bharat" else []} for n, i in enumerate(ids[:2], 1)]
        more = [{"scheme_id": ids[2], "rank": 3, "confidence": 0.5, "reason": "r", "reason_language": "en", "citations": []}] if len(ids) > 2 else []
        return httpx.Response(200, json={"recommendations": recs, "more": more, "mode": self.mode, "trace_id": "t",
                                         "fallback_reason": None if self.mode == "rag" else "llm_503"})


GOLDEN = [
    Case(id="up", profile={"state": "Uttar Pradesh"}, must_include=["pm_kisan"], must_not_include=["wb_annapurna_bhandar"]),
    Case(id="kl", profile={"state": "Kerala"}, must_include=["pm_kisan"], must_not_include=["ayushman_bharat"]),
    Case(id="hi", language="hi", profile={"state": "Kerala"}, expect={"reason_language": "hi"}),
]


@pytest.fixture
def golden_dir(tmp_path, monkeypatch):
    import yaml

    (tmp_path / "g.yaml").write_text(yaml.safe_dump([
        {"id": c.id, "profile": c.profile, "language": c.language, "must_include": c.must_include,
         "must_not_include": c.must_not_include, "expect": c.expect} for c in GOLDEN]))
    return tmp_path


def run(server, golden_dir, **kw):
    return runner.run("http://svc", "t", golden_dir, None, transport=httpx.MockTransport(server), **kw)


def test_runner_computes_per_case_results(golden_dir):
    srv = FakeServer()
    out = run(srv, golden_dir)
    by = {c["id"]: c for c in out["per_case"]}
    assert by["up"]["recall10"] == 1.0 and by["up"]["returned_ids"] == ["pm_kisan", "ayushman_bharat", "ghost_scheme"]
    assert by["up"]["violations"] == []
    assert by["kl"]["recall10"] == 0.0 and by["kl"]["violations"] == ["ayushman_bharat"]
    assert out["metrics"]["violation_rate"] == 0.5  # 2 cases have forbidden lists; "kl" violates
    assert out["metrics"]["recall@10"] == 0.5
    assert out["cases"] == 3 and out["tag"] == "t"


def test_runner_sends_no_cache_header_and_request_body(golden_dir):
    srv = FakeServer()
    run(srv, golden_dir)
    body, headers = srv.requests[0]
    assert headers["cache-control"] == "no-cache"
    assert body == {"profile": {"state": "Uttar Pradesh"}, "language": "en", "top_n": 8, "include_citations": True}


def test_runner_unknown_ids_checked_against_corpus(golden_dir, tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    for i in ["pm_kisan", "ayushman_bharat"]:
        (docs / f"{i}.md").write_text("x")
    out = runner.run("http://svc", "t", golden_dir, docs, transport=httpx.MockTransport(FakeServer()))
    assert {c["id"]: c["unknown_ids"] for c in out["per_case"]}["up"] == ["ghost_scheme"]
    assert out["metrics"]["unknown_id_rate"] == pytest.approx(1 / 3)


def test_runner_model_level_metrics_from_metrics_endpoint(golden_dir):
    out = run(FakeServer(), golden_dir)
    assert out["server_counters_available"] is True
    assert out["metrics"]["model_hallucination_rate"] == pytest.approx(3 / 30)
    out2 = run(FakeServer(metrics=False), golden_dir)
    assert out2["server_counters_available"] is False and out2["metrics"]["model_hallucination_rate"] is None


def test_runner_expectations_and_errors(golden_dir):
    srv = FakeServer()
    srv.lang_override = "en"  # server ignores the requested language
    out = run(srv, golden_dir)
    hi = next(c for c in out["per_case"] if c["id"] == "hi")
    assert hi["expect_failures"] and "reason_language" in hi["expect_failures"][0]
    assert out["metrics"]["expectation_pass_rate"] == pytest.approx(2 / 3)

    srv2 = FakeServer()
    srv2.fail_for = {"Kerala"}
    out2 = run(srv2, golden_dir)
    assert out2["metrics"]["error_rate"] == pytest.approx(2 / 3)
    assert {c["id"]: c["status"] for c in out2["per_case"]}["kl"] == 503


def test_runner_network_failure_is_recorded_not_raised(golden_dir):
    def boom(request):
        raise httpx.ConnectError("refused", request=request)

    out = runner.run("http://svc", "t", golden_dir, None, transport=httpx.MockTransport(boom))
    assert out["metrics"]["error_rate"] == 1.0 and out["per_case"][0]["error"].startswith("ConnectError")


def test_runner_fallback_rate(golden_dir):
    srv = FakeServer()
    srv.mode = "rules_only"
    assert run(srv, golden_dir)["metrics"]["fallback_rate"] == 1.0


def test_runner_limit_and_progress(golden_dir):
    seen = []
    out = run(FakeServer(), golden_dir, limit=2, progress=seen.append)
    assert out["cases"] == 2 and len(seen) == 2


# ------------------------------------------------------------------ reports + CLI
def _result(tag, **metrics):
    base = {"cases": 3.0, "recall@5": 0.5, "recall@10": 0.8, "violation_rate": 0.1, "latency_p50_ms": 1000.0, "fallback_rate": 0.2}
    base.update(metrics)
    return {"tag": tag, "target": "t", "timestamp": "now", "metrics": base, "per_case": [], "server_counters_available": False}


def test_compare_marks_better_and_worse():
    md = report.compare(_result("A"), _result("B", **{"recall@10": 0.9, "violation_rate": 0.3, "latency_p50_ms": 500.0}))
    assert "| recall@10 | 0.800 | 0.900 | better (+0.100) |" in md
    assert "| violation_rate | 0.100 | 0.300 | worse (+0.200) |" in md
    assert "| latency_p50_ms | 1,000 ms | 500 ms | better (-500 ms) |" in md
    assert "| fallback_rate | 0.200 | 0.200 |  |" in md  # unchanged -> blank


def test_summary_and_failures_text():
    r = _result("A")
    r["per_case"] = [{"id": "c1", "status": 200, "recall10": 0.5, "violations": ["x"], "unknown_ids": [], "expect_failures": [], "error": None},
                     {"id": "c2", "status": 200, "recall10": 1.0, "violations": [], "unknown_ids": [], "expect_failures": [], "error": None}]
    assert "| recall@10 | 0.800 |" in report.summary(r)
    assert report.failures(r) == ["- c1: recall@10=0.50; forbidden: ['x']"]


def test_cli_run_writes_results_and_enforces_thresholds(golden_dir, tmp_path, monkeypatch, capsys):
    out_file = tmp_path / "res.json"
    monkeypatch.setattr(runner, "run", lambda *a, **k: _result("cli"))
    assert cli.main(["run", "--tag", "cli", "--out", str(out_file), "--golden", str(golden_dir)]) == 0
    assert json.loads(out_file.read_text())["tag"] == "cli"
    assert cli.main(["run", "--tag", "cli", "--out", str(out_file), "--min-recall10", "0.95"]) == 1
    assert cli.main(["run", "--tag", "cli", "--out", str(out_file), "--max-violation", "0.05"]) == 1
    assert cli.main(["run", "--tag", "cli", "--out", str(out_file), "--min-recall10", "0.5", "--max-violation", "0.2"]) == 0


def test_cli_compare(tmp_path, capsys):
    a, b = tmp_path / "a.json", tmp_path / "b.json"
    a.write_text(json.dumps(_result("A")))
    b.write_text(json.dumps(_result("B", **{"recall@10": 1.0})))
    assert cli.main(["compare", str(a), str(b)]) == 0
    assert "A vs B" in capsys.readouterr().out
