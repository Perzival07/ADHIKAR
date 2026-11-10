import copy
import json
import logging
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient

from eligibility_service.config import Settings
from eligibility_service.contract_models import CitizenProfile
from eligibility_service.dsl import RuleError, validate_condition
from eligibility_service.engine import PROFILE_FIELDS, RULES_DIR, Engine, Rules
from eligibility_service.main import create_app
from eligibility_service.schemes import SchemeInfo

from .conftest import DOCS


def ids(engine, **kw):
    res = engine.evaluate(CitizenProfile(**kw))
    return {r.scheme_id for r in res if r.status == "eligible"}


def by_id(engine, sid, **kw):
    return next(r for r in engine.evaluate(CitizenProfile(**kw), [sid]))


# ----------------------------------------------------- scenarios from the Flutter test-suite
def test_maharashtra_woman_gets_ladki_bahin(engine):
    assert "mh_ladki_bahin" in ids(engine, state="Maharashtra", gender="Female", age=30, annualIncomeRange="< 1 Lakh")


def test_west_bengal_21f_schemes_but_not_annapurna(engine):
    got = ids(engine, state="West Bengal", gender="Female", age=21, occupation="Student", studentLevel="Higher Ed")
    assert {"wb_banglar_yuva_sathi", "wb_bhagini_nivedita"} <= got and "wb_annapurna_bhandar" not in got
    r = by_id(engine, "wb_annapurna_bhandar", state="West Bengal", gender="Female", age=21)
    assert r.status == "ineligible" and "minimum age of 25" in r.reasons[0]


def test_west_bengal_adult_woman_gets_annapurna(engine):
    assert "wb_annapurna_bhandar" in ids(engine, state="West Bengal", gender="Female", age=28)


def test_odisha_telangana_rajasthan_assam(engine):
    assert "or_subhadra" in ids(engine, state="Odisha", gender="Female", age=40, annualIncomeRange="< 1 Lakh")
    assert "ts_mahalakshmi" in ids(engine, state="Telangana", gender="Female", age=33, rationCard="BPL")
    assert "rj_maa_ayushman" in ids(engine, state="Rajasthan")
    assert any(i.startswith("as_") for i in ids(engine, state="Assam", gender="Female", age=26, annualIncomeRange="< 1 Lakh"))


def test_other_states_schemes_never_leak(engine):
    got = ids(engine, state="Odisha", gender="Female", age=40, annualIncomeRange="< 1 Lakh")
    assert not any(i.startswith(("kl_", "mh_", "wb_", "ts_")) for i in got)


def test_general_citizen_filters_out_farming_artisan_student(engine):
    got = ids(engine, occupation="Citizen")
    assert not ({"pm_kisan", "pm_vishwakarma", "pm_svanidhi", "post_matric_scholarship"} & got)


# ----------------------------------------------------- statuses, missing fields, filtering
def test_landless_farmer_is_unknown_with_missing_field(engine):
    r = by_id(engine, "pm_kisan", occupation="Farmer", landHoldingAcres=0)
    assert r.status == "unknown" and r.missing_fields == ["landHoldingAcres"] and 0 < r.score < 0.5
    assert by_id(engine, "pm_kisan", occupation="Farmer", landHoldingAcres=2.5).status == "eligible"
    assert by_id(engine, "pm_kisan", occupation="Citizen").status == "ineligible"


def test_superseded_scheme_is_ineligible(schemes, rules):
    s = dict(schemes)
    s["wb_lakshmir_bhandar"] = SchemeInfo(id="wb_lakshmir_bhandar", name="Lakshmir Bhandar", is_central=False, state_scope="West Bengal")
    r = Engine(s, rules).evaluate(CitizenProfile(state="West Bengal", gender="Female", age=40), ["wb_lakshmir_bhandar"])[0]
    assert r.status == "ineligible" and "superseded" in r.reasons[0]


def test_empty_state_makes_state_schemes_unknown(engine):
    r = by_id(engine, "kl_unknown_state_scheme" if False else next(i for i, s in engine.schemes.items() if not s.is_central and i not in engine.rules.specific), state="")
    assert r.status == "unknown" and r.missing_fields == ["state"]


def test_scheme_ids_filter_and_unknown_id(engine):
    res = engine.evaluate(CitizenProfile(), ["pm_kisan", "does_not_exist"])
    assert [r.scheme_id for r in res] == ["pm_kisan", "does_not_exist"]
    assert res[1].status == "ineligible" and "Unknown" in res[1].reasons[0]


def test_unverified_schemes_are_never_eligible(schemes, rules):
    s = dict(schemes)
    s["mystery"] = SchemeInfo(id="mystery", name="Mystery", status="unverified")
    r = Engine(s, rules).evaluate(CitizenProfile(), ["mystery"])[0]
    assert r.status == "ineligible" and "no verified metadata" in r.reasons[0]


def test_loader_ignores_translations_and_files_without_metadata(tmp_path):
    (tmp_path / "a.md").write_text('---\nscheme_id: "a"\nname: "A"\n---\n## Summary\nhi')
    (tmp_path / "a.hi.md").write_text('---\nscheme_id: "a"\nname: "ए"\nlanguage: "hi"\n---\nx')
    (tmp_path / "nometa.md").write_text("## Summary\nno front matter")
    (tmp_path / "README.md").write_text("# readme")
    (tmp_path / "folder").mkdir()
    (tmp_path / "folder" / "meta.yaml").write_text('scheme_id: "folder"\nname: "F"\nstate_scope: "Assam"\nis_central: false\n')
    from eligibility_service.schemes import load_schemes

    got = load_schemes(str(tmp_path))
    assert set(got) == {"a", "folder"} and got["folder"].state_scope == "Assam" and got["a"].name == "A"


def test_age_limits_from_metadata_enforced_in_generic_path(engine):
    # Asmita Yojana: Maharashtra girls aged 11-19
    assert by_id(engine, "mh_asmita_yojana", state="Maharashtra", gender="Female", age=15).status == "eligible"
    assert by_id(engine, "mh_asmita_yojana", state="Maharashtra", gender="Female", age=40).status == "ineligible"


# ----------------------------------------------------- rule files
def test_all_shipped_rule_files_validate_against_schema_and_dsl():
    rules = Rules.load()
    assert len(rules.specific) >= 41 and len(rules.generic) >= 10
    for f in RULES_DIR.glob("*.yaml"):
        assert yaml.safe_load(f.read_text())["version"] == 1


# Rules for schemes that are not in the corpus yet. They are dead until a document with that scheme_id is added.
# Do not add to this list to silence the test below: a rule keyed by a misspelt id silently never runs
# (e.g. `pb_ashirwad` vs the real `pb_ashirwad_scheme`), and the scheme falls through to the generic rules.
RULES_AWAITING_CORPUS = {
    "dl_mahila_samman", "mgnrega", "nsap_disability_pension", "nsap_widow_pension", "pm_suraksha_bima",
    "post_matric_scholarship", "rj_chiranjeevi", "up_abhyudaya", "wb_lakshmir_bhandar",
}


def test_every_scheme_rule_targets_a_scheme_in_the_corpus(schemes, rules):
    orphans = set(rules.specific) - set(schemes) - RULES_AWAITING_CORPUS
    assert not orphans, f"rules keyed by ids that match no scheme document (typo?): {sorted(orphans)}"
    assert not RULES_AWAITING_CORPUS & set(schemes), "a scheme was added to the corpus: drop it from RULES_AWAITING_CORPUS"


def _write_rules(tmp_path, mutate):
    for f in RULES_DIR.iterdir():
        (tmp_path / f.name).write_text(f.read_text())
    target = tmp_path / "central.yaml"
    data = yaml.safe_load(target.read_text())
    mutate(data)
    target.write_text(yaml.safe_dump(data))
    return tmp_path


@pytest.mark.parametrize("mutate, message", [
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(when={"bogus": 1}), "unknown operator"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(when={"eq": ["nonexistentField", 1]}), "unknown profile field"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(score=0.2), "inconsistent"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(reason="Hello {nope}"), "unknown profile field in template"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(status="maybe"), "maybe"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(when={"all": [], }), "non-empty list"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].update(when={"python": "not_registered"}), "not registered"),
    (lambda d: d["schemes"]["pm_kisan"]["outcomes"][0].pop("reason"), "reason"),
])
def test_invalid_rules_are_rejected(tmp_path, mutate, message):
    with pytest.raises(RuleError, match=message):
        Rules.load(_write_rules(tmp_path, mutate))


def test_duplicate_scheme_rule_rejected(tmp_path):
    d = _write_rules(tmp_path, lambda data: None)
    state = yaml.safe_load((d / "state.yaml").read_text())
    state["schemes"]["pm_kisan"] = copy.deepcopy({"outcomes": []})
    (d / "state.yaml").write_text(yaml.safe_dump(state))
    with pytest.raises(RuleError, match="duplicate"):
        Rules.load(d)


def test_dsl_condition_validator_examples():
    validate_condition({"all": [{"gte": ["age", 18]}, {"in": ["state", ["Assam"]]}, {"not": {"is": "isFarmer"}}]}, PROFILE_FIELDS)
    with pytest.raises(RuleError):
        validate_condition({"gte": ["age", 18], "lt": ["age", 5]}, PROFILE_FIELDS)  # two keys


def test_python_escape_hatch_registry_works(schemes, rules, monkeypatch):
    from eligibility_service import predicates

    monkeypatch.setitem(predicates.PREDICATES, "always", lambda ctx, scheme: True)
    validate_condition({"python": "always"}, PROFILE_FIELDS)
    from eligibility_service.dsl import evaluate

    assert evaluate({"python": "always"}, {}, next(iter(schemes.values()))) is True


# ----------------------------------------------------- API
def client(**kw):
    return TestClient(create_app(Settings(docs_dir=str(DOCS), **kw)))


def test_api_eligibility_and_filtering():
    c = client()
    body = {"profile": {"state": "Rajasthan"}, "scheme_ids": ["rj_maa_ayushman", "pm_kisan"]}
    r = c.post("/v1/eligibility", json=body)
    assert r.status_code == 200
    res = {x["scheme_id"]: x for x in r.json()["results"]}
    assert res["rj_maa_ayushman"]["status"] == "eligible" and res["pm_kisan"]["status"] == "ineligible"
    assert res["rj_maa_ayushman"]["score"] == 1.0 and res["rj_maa_ayushman"]["reasons"]


def test_api_rejects_pii_fields():
    assert client().post("/v1/eligibility", json={"profile": {"state": "Assam", "name": "Rajesh"}}).status_code == 422


def test_api_full_evaluation_covers_whole_corpus():
    r = client().post("/v1/eligibility", json={"profile": {}})
    assert len(r.json()["results"]) == 313


def test_reload_endpoint_and_bad_reload_keeps_old_state(tmp_path):
    (tmp_path / "a.md").write_text('---\nscheme_id: "a"\nname: "A"\ncategory: "x"\n---\n## Summary\ns\n\n## Eligibility\nYou qualify.\n')
    c = TestClient(create_app(Settings(docs_dir=str(tmp_path))))
    assert c.get("/ready").json()["checks"]["schemes_loaded"] == 1
    (tmp_path / "b.md").write_text('---\nscheme_id: "b"\nname: "B"\n---\n## Summary\ns')
    assert c.post("/v1/admin/reload").json() == {"schemes": 2}
    assert len(c.post("/v1/eligibility", json={"profile": {}}).json()["results"]) == 2


def test_ready_false_when_no_schemes(tmp_path):
    assert TestClient(create_app(Settings(docs_dir=str(tmp_path)))).get("/ready").status_code == 503


def test_no_raw_profile_fields_in_logs(capsys):
    c = client()
    c.post("/v1/eligibility", json={"profile": {"state": "Assam", "socialCategory": "SC", "annualIncomeRange": "< 1 Lakh", "disabilityStatus": "40%+ (Divyangjan)"}})
    out = capsys.readouterr().out
    assert "profile_hash" in out
    for secret in ("socialCategory", "annualIncomeRange", "Divyangjan", "< 1 Lakh"):
        assert secret not in out


def test_docs_path_default_resolves_to_backend_data():
    assert Path(DOCS).exists() and (Path(DOCS) / "pm_kisan.md").exists()
    assert json.loads(json.dumps(Settings().model_dump()))
    _ = logging


def test_delhi_student_scheme_accepts_both_state_spellings(schemes, rules):
    s = dict(schemes)
    s["dl_vidyarthi_pratibha"] = SchemeInfo(id="dl_vidyarthi_pratibha", name="Vidyarthi Pratibha", is_central=False, state_scope="Delhi")
    eng = Engine(s, rules)
    for state in ("Delhi", "Delhi (NCT)"):
        r = eng.evaluate(CitizenProfile(state=state, occupation="Student", studentLevel="Higher Ed", socialCategory="SC"), ["dl_vidyarthi_pratibha"])[0]
        assert r.status == "eligible", state
    assert eng.evaluate(CitizenProfile(state="Kerala", occupation="Student", socialCategory="SC"), ["dl_vidyarthi_pratibha"])[0].status == "ineligible"
