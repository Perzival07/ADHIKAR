# ADR 0004: Server-side accounts with ES256 JWT + rotating refresh tokens
**Status:** accepted
**Context:** accounts lived only on each phone and OTP email was sent from the app with embedded credentials.
**Decision:** auth-service (Postgres) issues short-lived ES256 access tokens and opaque rotating refresh tokens;
other services verify via JWKS. OTP is sent by the server.
**Consequences:** no shared secrets between services; key rotation is a deploy; the app keeps an offline demo mode when
no auth server is configured.
