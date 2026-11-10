"""The Python rules must reproduce the Flutter SchemeEngine exactly (eligible set, scores and reasons).

Fixture produced by:  dart run tool/dump_engine_parity.dart <parity_profiles.json> <dart_parity.json>
"""
import json
from pathlib import Path

import pytest

from eligibility_service.contract_models import CitizenProfile

FIX = Path(__file__).parent / "fixtures" / "dart_parity.json"
CASES = json.loads(FIX.read_text())


def test_fixture_is_substantial():
    assert len(CASES) >= 400


@pytest.mark.parametrize("i", range(len(CASES)))
def test_profile_matches_dart(engine, i):
    case = CASES[i]
    profile = CitizenProfile(**case["profile"])
    results = engine.evaluate(profile)
    py = {r.scheme_id: r for r in results if r.status == "eligible"}
    dart = case["eligible"]
    assert set(py) == set(dart), (
        f"profile {case['profile']}\nonly python: {sorted(set(py) - set(dart))}\nonly dart: {sorted(set(dart) - set(py))}"
    )
    for sid, d in dart.items():
        assert py[sid].score == pytest.approx(d["score"]), sid
        assert py[sid].reasons == [d["reason"]], sid
