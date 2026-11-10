from pathlib import Path

import pytest

from eligibility_service.config import Settings
from eligibility_service.engine import Engine, Rules
from eligibility_service.schemes import load_schemes

DOCS = Path(__file__).resolve().parents[3] / "data" / "scheme_docs"


@pytest.fixture(scope="session")
def schemes():
    s = load_schemes(str(DOCS))
    if not s:
        pytest.skip("exported scheme docs not present")
    return s


@pytest.fixture(scope="session")
def rules():
    return Rules.load()


@pytest.fixture
def engine(schemes, rules):
    return Engine(schemes, rules)


@pytest.fixture
def settings():
    return Settings(docs_dir=str(DOCS))
