import json
import re
import subprocess
import sys
from pathlib import Path

import pytest
import yaml
from openapi_spec_validator import validate

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import contract_models as m

SPECS = sorted((ROOT / "openapi").glob("*.yaml"))


def test_six_specs_exist():
    assert len(SPECS) == 7  # six pipeline services + auth-service


@pytest.mark.parametrize("spec", SPECS, ids=lambda p: p.stem)
def test_openapi_spec_is_valid(spec):
    validate(yaml.safe_load(spec.read_text()))


def test_generated_files_not_stale():
    r = subprocess.run([sys.executable, str(ROOT / "generate.py"), "--check"], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr


def test_service_copies_in_sync():
    r = subprocess.run([sys.executable, str(ROOT / "sync.py"), "--check"], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr


def test_citizen_profile_matches_flutter_to_json():
    dart = (ROOT.parents[1] / "lib/core/models/citizen_profile.dart").read_text()
    body = dart[dart.index("toJson()"):]
    keys = set(re.findall(r"'(\w+)':", body))
    assert keys == set(m.CitizenProfile.model_fields), keys ^ set(m.CitizenProfile.model_fields)


def test_citizen_profile_rejects_pii_fields():
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        m.CitizenProfile(name="Rajesh", phone="9876543210")


def test_json_schemas_written():
    for name in ["CitizenProfile", "SchemeDocMeta", "Chunk", "EligibilityResult", "Recommendation"]:
        assert json.loads((ROOT / "schemas" / f"{name}.json").read_text())["type"] == "object"
