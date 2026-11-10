# Security

## Accounts and sessions (auth-service)
- Passwords: argon2id; minimum 8 characters; account lockout after 5 failures (15 min) plus per-IP limits.
- OTP: 6 digits, stored only as HMAC, 5-minute expiry, 5 attempts, single use, 60 s resend cooldown, 5/hour cap.
  Sent by the server (SMTP); the app never holds email credentials. Production refuses the console backend.
- No account enumeration: OTP requests and login errors look identical whether or not the account exists.
- Tokens: ES256 access tokens (15 min, in memory on the device); opaque refresh tokens (30 days, stored hashed on
  the server and in the iOS Keychain / Android Keystore on the device), rotated on every use. Replaying a rotated
  token revokes that whole session family.
- Services verify tokens with the public JWKS; no shared secrets between services. Key rotation: deploy the new key;
  verifiers refetch the JWKS on an unknown `kid` (throttled).
- Right to erasure: `DELETE /v1/users/me` (and "Delete my account" in the app) removes the account and sessions.

## Platform
- Containers: non-root (UID 10001), read-only root filesystem, all capabilities dropped, seccomp RuntimeDefault;
  namespace enforces Pod Security "restricted". No service-account tokens mounted.
- Network: default-deny ingress; each pod accepts traffic only from its callers (verified on a live cluster).
  `/metrics` and `/v1/admin/*` are not routed by the ingress; the reco metrics endpoint also needs a bearer token.
- Supply chain: pinned dependencies (`backend/constraints.txt`), `pip-audit` in CI, Trivy scan of every image
  (fails on fixable critical/high), SBOM + signed build provenance on release.
- Production config guardrails: auth-service refuses to start without a JWT key, OTP secret, SMTP, Postgres, and
  with demo users or `*` CORS.

## Data handling
- The recommendation API accepts only profile answers (state, age, occupation, income band, category, ...);
  unknown fields such as name/phone/email are rejected by schema. Logs and metrics contain a profile hash, never
  the answers (enforced by an AST-based test over every log call).
- Saved wizard answers on the account (`profile`) are opt-in.

## Secrets you must manage
JWT private key, OTP secret, database URL, SMTP credentials, reco admin + metrics tokens. Rotate the JWT key at least
yearly and immediately on suspicion; rotating the OTP secret only invalidates codes in flight.
The old Gmail app password and Gemini key that were once in this repository must be revoked/rotated by the owner.
