from datetime import UTC, datetime, timedelta

import jwt
import pytest
import sqlalchemy as sa
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext

from auth_service.config import ConfigError, Settings
from auth_service.db import Base
from auth_service.security import SigningKey

from .conftest import bearer, last_code, signup


# ------------------------------------------------------------------ schema
def test_migration_matches_models(db_url):
    engine = sa.create_engine(db_url.replace("+aiosqlite", ""))
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], diff


# ------------------------------------------------------------------ signup / OTP
def test_signup_issues_tokens_and_profile(client, sender):
    d = signup(client, sender, state="Assam", socialCategory="ST", occupation="Farmer")
    assert d["token_type"] == "bearer" and d["expires_in"] == 900 and len(d["refresh_token"]) > 40
    u = d["user"]
    assert u["email"] == "asha@example.com" and u["state"] == "Assam" and u["isVerified"] is True
    me = client.get("/v1/users/me", headers=bearer(d["access_token"])).json()
    assert me["id"] == u["id"] and me["socialCategory"] == "ST"


def test_access_token_verifies_against_published_jwks(client, sender):
    tok = signup(client, sender)["access_token"]
    jwks = client.get("/.well-known/jwks.json").json()
    key = jwt.PyJWK(jwks["keys"][0])
    claims = jwt.decode(tok, key.key, algorithms=["ES256"], audience="adhikar-api", issuer="adhikar-auth")
    assert claims["sub"] and claims["exp"] - claims["iat"] == 900
    assert jwt.get_unverified_header(tok)["kid"] == jwks["keys"][0]["kid"]
    assert "d" not in jwks["keys"][0]  # never publish the private part


def test_email_is_normalised(client, sender):
    signup(client, sender, email="Asha@Example.COM")
    assert client.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"}).status_code == 200


def test_no_account_enumeration_via_otp(make, sender):
    client = make(otp_resend_cooldown=0)
    signup(client, sender)
    n = len(sender.outbox)
    existing = client.post("/v1/auth/otp/request", json={"email": "asha@example.com", "purpose": "signup"})
    unknown = client.post("/v1/auth/otp/request", json={"email": "nobody@example.com", "purpose": "login"})
    assert existing.status_code == unknown.status_code == 202
    assert existing.json() == unknown.json()
    assert len(sender.outbox) == n  # nothing was sent in either case


def test_otp_cooldown_and_hourly_cap(make, sender):
    with make(otp_resend_cooldown=60) as c:
        assert c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"}).status_code == 202
        r = c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
        assert r.status_code == 429 and 0 < int(r.headers["retry-after"]) <= 60
    with make(otp_resend_cooldown=0, otp_max_per_hour=3) as c:
        codes = [c.post("/v1/auth/otp/request", json={"email": "b@example.com", "purpose": "signup"}).status_code for _ in range(4)]
        assert codes == [202, 202, 202, 429]


def test_only_latest_code_works(make, sender):
    with make(otp_resend_cooldown=0) as c:
        c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
        old = last_code(sender, "a@example.com")
        c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
        body = {"email": "a@example.com", "password": "longenough1", "name": "A"}
        new = last_code(sender, "a@example.com")
        if old != new:
            assert c.post("/v1/auth/signup", json={**body, "code": old}).status_code == 400
        assert c.post("/v1/auth/signup", json={**body, "code": new}).status_code == 201


def test_wrong_code_attempts_are_limited(make, sender):
    with make(otp_attempts=3) as c:
        c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
        code = last_code(sender, "a@example.com")
        wrong = f"{(int(code) + 1) % 1_000_000:06d}"
        body = {"email": "a@example.com", "password": "longenough1", "name": "A"}
        for _ in range(3):
            assert c.post("/v1/auth/signup", json={**body, "code": wrong}).status_code == 400
        r = c.post("/v1/auth/signup", json={**body, "code": code})  # even the right code is now dead
        assert r.status_code == 400 and "Request a new one" in r.json()["detail"]


def test_expired_code_rejected(make, sender):
    with make(otp_ttl=-1) as c:
        c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
        body = {"email": "a@example.com", "password": "longenough1", "name": "A", "code": last_code(sender, "a@example.com")}
        assert c.post("/v1/auth/signup", json=body).status_code == 400


def test_code_is_single_use(client, sender):
    client.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
    body = {"email": "a@example.com", "password": "longenough1", "name": "A", "code": last_code(sender, "a@example.com")}
    assert client.post("/v1/auth/signup", json=body).status_code == 201
    assert client.post("/v1/auth/signup", json=body).status_code == 400


def test_password_policy_and_validation(client, sender):
    client.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
    code = last_code(sender, "a@example.com")
    r = client.post("/v1/auth/signup", json={"email": "a@example.com", "password": "short", "name": "A", "code": code})
    assert r.status_code == 422 and "at least 8" in r.json()["detail"]
    assert client.post("/v1/auth/signup", json={"email": "a@example.com", "password": "longenough1", "name": "A", "code": code,
                                                 "isAdmin": True}).status_code == 422  # unknown fields rejected
    assert client.post("/v1/auth/otp/request", json={"email": "not-an-email"}).status_code == 422


def test_passwords_are_hashed_with_argon2(client, sender, db_url):
    signup(client, sender)
    engine = sa.create_engine(db_url.replace("+aiosqlite", ""))
    with engine.connect() as conn:
        stored = conn.execute(sa.text("select password_hash from users")).scalar_one()
        otp = conn.execute(sa.text("select code_hash from otp_challenges")).scalar_one()
    assert stored.startswith("$argon2id$") and "correct horse" not in stored
    assert len(otp) == 64 and not otp.isdigit()  # HMAC, never the code itself


# ------------------------------------------------------------------ login
def test_password_login_and_generic_errors(client, sender):
    signup(client, sender)
    ok = client.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"})
    assert ok.status_code == 200 and ok.json()["user"]["name"] == "Asha"
    bad_pw = client.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "wrong"})
    no_user = client.post("/v1/auth/login", json={"identifier": "ghost@example.com", "password": "wrong"})
    assert bad_pw.status_code == no_user.status_code == 401
    assert bad_pw.json() == no_user.json() == {"detail": "Invalid credentials."}


def test_lockout_after_repeated_failures(make, sender, db_url):
    with make(max_failed_logins=3, lockout_seconds=600) as c:
        signup(c, sender)
        for _ in range(3):
            c.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "nope"})
        r = c.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"})
        assert r.status_code == 429 and int(r.headers["retry-after"]) > 0
        engine = sa.create_engine(db_url.replace("+aiosqlite", ""))
        with engine.begin() as conn:
            conn.execute(sa.text("update users set locked_until = :t"), {"t": datetime.now(UTC) - timedelta(seconds=1)})
        assert c.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"}).status_code == 200


def test_otp_login(client, sender):
    signup(client, sender)
    assert client.post("/v1/auth/otp/request", json={"email": "asha@example.com", "purpose": "login"}).status_code == 202
    r = client.post("/v1/auth/login/otp", json={"email": "asha@example.com", "code": last_code(sender, "asha@example.com")})
    assert r.status_code == 200 and r.json()["user"]["email"] == "asha@example.com"


def test_demo_seed_supports_phone_login(make):
    with make(seed_demo_users=True) as c:
        r = c.post("/v1/auth/login", json={"identifier": "9876543210", "password": "password123"})
        assert r.status_code == 200 and r.json()["user"]["name"] == "Priya Patel"
        assert c.post("/v1/auth/login", json={"identifier": "citizen@adhikar.gov.in", "password": "password123"}).status_code == 200


# ------------------------------------------------------------------ refresh tokens
def test_refresh_rotates_and_detects_reuse(client, sender):
    first = signup(client, sender)
    r1 = client.post("/v1/auth/token/refresh", json={"refresh_token": first["refresh_token"]})
    assert r1.status_code == 200 and r1.json()["refresh_token"] != first["refresh_token"]
    # replaying the rotated-away token = theft: the whole session family dies
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": first["refresh_token"]}).status_code == 401
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": r1.json()["refresh_token"]}).status_code == 401


def test_reuse_detection_does_not_kill_other_devices(client, sender):
    phone = signup(client, sender)
    laptop = client.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"}).json()
    client.post("/v1/auth/token/refresh", json={"refresh_token": phone["refresh_token"]})
    client.post("/v1/auth/token/refresh", json={"refresh_token": phone["refresh_token"]})  # reuse on the phone family
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": laptop["refresh_token"]}).status_code == 200


def test_logout_and_logout_all(client, sender):
    a = signup(client, sender)
    b = client.post("/v1/auth/login", json={"identifier": "asha@example.com", "password": "correct horse 9"}).json()
    assert client.post("/v1/auth/logout", json={"refresh_token": a["refresh_token"]}).status_code == 204
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": a["refresh_token"]}).status_code == 401
    assert client.post("/v1/auth/logout-all", headers=bearer(b["access_token"])).status_code == 204
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": b["refresh_token"]}).status_code == 401


def test_expired_refresh_token(make, sender):
    with make(refresh_token_ttl=-1) as c:
        d = signup(c, sender)
        assert c.post("/v1/auth/token/refresh", json={"refresh_token": d["refresh_token"]}).status_code == 401


# ------------------------------------------------------------------ bearer tokens
def test_bad_tokens_rejected(client, sender):
    good = signup(client, sender)["access_token"]
    other_key = SigningKey.load("").issue("x", "adhikar-auth", "adhikar-api", 60)
    wrong_aud = client.app.state.key.issue(good and "x", "adhikar-auth", "someone-else", 60)
    expired = client.app.state.key.issue("x", "adhikar-auth", "adhikar-api", -10)
    for tok in ("garbage", other_key, wrong_aud, expired, good[:-4] + "AAAA"):
        r = client.get("/v1/users/me", headers=bearer(tok))
        assert r.status_code == 401 and r.headers["www-authenticate"] == "Bearer"
    assert client.get("/v1/users/me").status_code == 401


# ------------------------------------------------------------------ profile + deletion
def test_update_profile(client, sender):
    tok = signup(client, sender)["access_token"]
    r = client.patch("/v1/users/me", headers=bearer(tok), json={"name": "Asha K", "state": "Kerala", "profile": {"age": 30}})
    assert r.status_code == 200 and r.json()["name"] == "Asha K" and r.json()["profile"] == {"age": 30}
    assert client.patch("/v1/users/me", headers=bearer(tok), json={"profile": {}}).json()["profile"] is None
    assert client.patch("/v1/users/me", headers=bearer(tok), json={"email": "x@y.z"}).status_code == 422  # not editable here


def test_delete_account_removes_everything(client, sender, db_url):
    d = signup(client, sender)
    assert client.delete("/v1/users/me", headers=bearer(d["access_token"])).status_code == 204
    assert client.get("/v1/users/me", headers=bearer(d["access_token"])).status_code == 401
    assert client.post("/v1/auth/token/refresh", json={"refresh_token": d["refresh_token"]}).status_code == 401
    engine = sa.create_engine(db_url.replace("+aiosqlite", ""))
    with engine.connect() as conn:
        for table in ("users", "refresh_tokens", "otp_challenges"):
            assert conn.execute(sa.text(f"select count(*) from {table}")).scalar_one() == 0


# ------------------------------------------------------------------ abuse + ops
def test_ip_rate_limit(make):
    with make(rate_limit_per_minute=3) as c:
        codes = [c.post("/v1/auth/login", json={"identifier": "x@y.zz", "password": "p"}).status_code for _ in range(5)]
    assert codes == [401, 401, 401, 429, 429]


def test_ready_health_metrics(client, sender):
    assert client.get("/health").json()["status"] == "ok"
    assert client.get("/ready").json()["checks"] == {"database": True}
    signup(client, sender)
    text = client.get("/metrics").text
    assert 'auth_events_total{event="signup",outcome="ok"} 1' in text and "asha" not in text


def test_otp_code_never_logged_outside_development(make, sender, capsys):
    with make() as c:
        c.post("/v1/auth/otp/request", json={"email": "a@example.com", "purpose": "signup"})
    code = last_code(sender, "a@example.com")
    out = capsys.readouterr().out
    assert code not in out and "a@example.com" not in out and "a***@example.com" in out


@pytest.mark.parametrize("override, message", [
    ({}, "AUTH_JWT_PRIVATE_KEY"),
    ({"jwt_private_key": "k"}, "AUTH_OTP_SECRET"),
    ({"jwt_private_key": "k", "otp_secret": "s" * 40}, "console"),
    ({"jwt_private_key": "k", "otp_secret": "s" * 40, "email_backend": "smtp"}, "Postgres"),
])
def test_production_guardrails(override, message):
    with pytest.raises(ConfigError, match=message):
        Settings(env="production", **override)


def test_production_config_accepted_when_complete():
    s = Settings(env="production", jwt_private_key="k", otp_secret="s" * 40, email_backend="smtp",
                 database_url="postgresql+asyncpg://u:p@db/auth", cors_origins="https://app.adhikar.example")
    assert s.is_production


def test_private_key_accepted_as_pem_escaped_or_base64():
    import base64

    from auth_service.security import generate_private_key_pem

    pem = generate_private_key_pem()
    kids = {SigningKey.load(v).kid for v in (pem, pem.replace("\n", "\\n"), base64.b64encode(pem.encode()).decode())}
    assert len(kids) == 1  # same key whichever way it was written
    with pytest.raises(ValueError):
        SigningKey.load("not a key at all!!")


def test_configured_key_survives_restarts(make, sender):
    from auth_service.security import generate_private_key_pem

    pem = generate_private_key_pem()
    with make(jwt_private_key=pem) as c1:
        tok = signup(c1, sender)["access_token"]
    with make(jwt_private_key=pem) as c2:  # another replica / a restart
        assert c2.get("/v1/users/me", headers=bearer(tok)).status_code == 200
