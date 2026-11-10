"""Passwords (argon2id), OTP codes (HMAC), opaque refresh tokens and ES256 access tokens."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
import uuid
from dataclasses import dataclass

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

_ph = PasswordHasher()  # argon2id with library defaults
# a real hash of a random password: lets "unknown user" logins take as long as real ones (no timing oracle)
_DUMMY_HASH = _ph.hash(secrets.token_urlsafe(16))


def hash_password(pw: str) -> str:
    return _ph.hash(pw)


def verify_password(stored: str | None, pw: str) -> bool:
    try:
        return _ph.verify(stored or _DUMMY_HASH, pw) and stored is not None
    except (VerificationError, InvalidHashError):
        return False


def new_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def otp_hash(secret: str, email: str, purpose: str, code: str) -> str:
    return hmac.new(secret.encode(), f"{email}|{purpose}|{code}".encode(), hashlib.sha256).hexdigest()


def new_refresh_token() -> tuple[str, str]:
    """Returns (token for the client, sha256 to store)."""
    tok = secrets.token_urlsafe(48)
    return tok, hashlib.sha256(tok.encode()).hexdigest()


def hash_refresh(tok: str) -> str:
    return hashlib.sha256(tok.encode()).hexdigest()


@dataclass
class SigningKey:
    private: ec.EllipticCurvePrivateKey
    kid: str

    @classmethod
    def load(cls, pem: str) -> SigningKey:
        pem = normalise_pem(pem)
        if pem:
            key = serialization.load_pem_private_key(pem.encode(), password=None)
            if not isinstance(key, ec.EllipticCurvePrivateKey) or key.curve.name != "secp256r1":
                raise ValueError("AUTH_JWT_PRIVATE_KEY must be an EC P-256 private key (ES256)")
        else:
            key = ec.generate_private_key(ec.SECP256R1())
        return cls(key, cls._kid(key))

    @staticmethod
    def _kid(key: ec.EllipticCurvePrivateKey) -> str:
        jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(key.public_key()))
        canonical = json.dumps({k: jwk[k] for k in ("crv", "kty", "x", "y")}, separators=(",", ":"), sort_keys=True)
        return base64.urlsafe_b64encode(hashlib.sha256(canonical.encode()).digest()).decode().rstrip("=")  # RFC 7638

    def jwks(self) -> dict:
        jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(self.private.public_key()))
        jwk.update(kid=self.kid, use="sig", alg="ES256")
        return {"keys": [jwk]}

    def issue(self, sub: str, issuer: str, audience: str, ttl: int, extra: dict | None = None) -> str:
        now = int(time.time())
        claims = {"sub": sub, "iss": issuer, "aud": audience, "iat": now, "nbf": now, "exp": now + ttl, "jti": uuid.uuid4().hex}
        claims.update(extra or {})
        return jwt.encode(claims, self.private, algorithm="ES256", headers={"kid": self.kid})

    def verify(self, token: str, issuer: str, audience: str) -> dict:
        return jwt.decode(token, self.private.public_key(), algorithms=["ES256"], issuer=issuer, audience=audience,
                          options={"require": ["exp", "iat", "sub", "iss", "aud"]})


def normalise_pem(value: str) -> str:
    """Accept a PEM as-is, with escaped newlines (single-line env files), or base64-encoded."""
    v = (value or "").strip()
    if not v:
        return ""
    if "\\n" in v:
        v = v.replace("\\n", "\n")
    if not v.startswith("-----BEGIN"):
        try:
            v = base64.b64decode(v, validate=True).decode()
        except (ValueError, UnicodeDecodeError) as e:
            raise ValueError("AUTH_JWT_PRIVATE_KEY is neither PEM nor base64-encoded PEM") from e
    return v


def generate_private_key_pem() -> str:
    key = ec.generate_private_key(ec.SECP256R1())
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
