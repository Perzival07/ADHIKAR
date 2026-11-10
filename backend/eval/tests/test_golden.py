"""The golden set itself must be trustworthy: valid ids, no contradictions, and consistent with the rules."""
from pathlib import Path

import pytest

from eval.golden import GoldenError, load_golden
from eval.runner import corpus_ids

DOCS = Path(__file__).resolve().parents[2] / "data" / "scheme_docs"
CASES = load_golden()


def test_golden_set_is_substantial_and_diverse():
    assert len(CASES) >= 40
    states = {c.profile.get("state") for c in CASES}
    assert len(states) >= 15 and "All India" in states
    assert {c.profile.get("gender") for c in CASES} >= {"Female", "Male"}
    assert {c.language for c in CASES} >= {"en", "hi", "ta"}
    assert {c.profile.get("occupation") for c in CASES} >= {"Farmer", "Student", "Salaried", "Street Vendor"}
    assert sum(1 for c in CASES if c.must_include) >= 35 and sum(1 for c in CASES if c.must_not_include) >= 20


@pytest.mark.skipif(not DOCS.exists(), reason="exported corpus missing")
def test_all_referenced_scheme_ids_exist_in_the_corpus():
    known = corpus_ids(DOCS)
    assert known and len(known) == 313
    for c in CASES:
        missing = [i for i in c.must_include + c.must_not_include if i not in known]
        assert not missing, f"{c.id}: unknown scheme ids {missing}"


@pytest.mark.skipif(not DOCS.exists(), reason="exported corpus missing")
def test_golden_expectations_agree_with_the_eligibility_rules():
    from eligibility_service.contract_models import CitizenProfile
    from eligibility_service.engine import Engine, Rules
    from eligibility_service.schemes import load_schemes

    engine = Engine(load_schemes(str(DOCS)), Rules.load())
    for c in CASES:
        res = {r.scheme_id: r.status for r in engine.evaluate(CitizenProfile(**c.profile))}
        for sid in c.must_include:
            assert res[sid] in ("eligible", "unknown"), f"{c.id}: rules say {sid} is {res[sid]}"
        for sid in c.must_not_include:
            assert res[sid] == "ineligible", f"{c.id}: rules say {sid} is {res[sid]}, expected ineligible"


def test_loader_rejects_bad_cases(tmp_path):
    (tmp_path / "a.yaml").write_text("- id: x\n  profile: {}\n  bogus: 1\n")
    with pytest.raises(GoldenError, match="unknown keys"):
        load_golden(tmp_path)
    (tmp_path / "a.yaml").write_text("- id: x\n  profile: {}\n  must_include: [a]\n  must_not_include: [a]\n")
    with pytest.raises(GoldenError, match="both required and forbidden"):
        load_golden(tmp_path)
    (tmp_path / "a.yaml").write_text("- id: x\n  profile: {}\n- id: x\n  profile: {}\n")
    with pytest.raises(GoldenError, match="duplicate"):
        load_golden(tmp_path)
    (tmp_path / "a.yaml").write_text("- profile: {}\n")
    with pytest.raises(GoldenError, match="`id` and `profile`"):
        load_golden(tmp_path)


def test_corpus_ids_handles_language_suffixes_and_folders(tmp_path):
    for n in ["a.md", "a.hi.md", "b.md", "README.md", "c.v2.md"]:
        (tmp_path / n).write_text("x")
    (tmp_path / "folder").mkdir()
    assert corpus_ids(tmp_path) == {"a", "b", "c.v2", "folder"}
    assert corpus_ids(tmp_path / "missing") is None
