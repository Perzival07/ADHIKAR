from __future__ import annotations

from starlette.types import Scope


def client_key(scope: Scope, trust_forwarded: bool) -> str:
    """Client identity for rate limiting. Behind a reverse proxy every request has the proxy's IP, so
    `trust_forwarded` (only enable it when a proxy you control sets the header) uses the first X-Forwarded-For hop."""
    if trust_forwarded:
        for k, v in scope.get("headers", []):
            if k == b"x-forwarded-for":
                first = v.decode("latin-1").split(",")[0].strip()
                if first:
                    return first[:64]
    return (scope.get("client") or ("unknown", 0))[0]
