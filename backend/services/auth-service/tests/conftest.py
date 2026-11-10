import fakeredis.aioredis
import pytest
from fastapi.testclient import TestClient

from auth_service.__main__ import migrate
from auth_service.config import Settings
from auth_service.email import MemorySender
from auth_service.main import create_app


@pytest.fixture
def db_url(tmp_path):
    url = f"sqlite+aiosqlite:///{tmp_path}/auth.db"
    migrate(url)  # the real Alembic migration, not create_all
    return url


@pytest.fixture
def sender():
    return MemorySender()


@pytest.fixture
def make(db_url, sender):
    def _make(**kw):
        kw.setdefault("rate_limit_per_minute", 1000)
        s = Settings(database_url=db_url, otp_secret="x" * 40, **kw)
        return TestClient(create_app(s, sender=sender, redis=fakeredis.aioredis.FakeRedis()))

    return _make


@pytest.fixture
def client(make):
    with make() as c:
        yield c


def last_code(sender, email):
    return next(code for to, code, _ in reversed(sender.outbox) if to == email.strip().lower())


def signup(client, sender, email="asha@example.com", password="correct horse 9", **extra):
    assert client.post("/v1/auth/otp/request", json={"email": email, "purpose": "signup"}).status_code == 202
    body = {"email": email, "code": last_code(sender, email), "password": password, "name": "Asha", **extra}
    r = client.post("/v1/auth/signup", json=body)
    assert r.status_code == 201, r.text
    return r.json()


def bearer(tok):
    return {"Authorization": f"Bearer {tok}"}
