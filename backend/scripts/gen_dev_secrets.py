"""Write random secrets for the Kubernetes dev overlay (deploy/k8s/overlays/dev/secrets/*.env, git-ignored).

Never use these for production: the prod overlay expects secrets from your secret manager.
"""
import base64
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services" / "auth-service" / "src"))
from auth_service.security import generate_private_key_pem

out = Path(__file__).resolve().parents[2] / "deploy" / "k8s" / "overlays" / "dev" / "secrets"
out.mkdir(parents=True, exist_ok=True)
pg = secrets.token_urlsafe(24)
files = {
    "postgres.env": {"POSTGRES_PASSWORD": pg},
    "auth.env": {
        "AUTH_DATABASE_URL": f"postgresql+asyncpg://adhikar:{pg}@postgres:5432/auth",
        "AUTH_JWT_PRIVATE_KEY": base64.b64encode(generate_private_key_pem().encode()).decode(),
        "AUTH_OTP_SECRET": secrets.token_hex(32),
    },
    "reco.env": {"RECO_ADMIN_TOKEN": secrets.token_hex(24), "RECO_METRICS_TOKEN": secrets.token_hex(24)},
    "shared.env": {"REDIS_URL": "redis://redis:6379/0", "REDIS_URL_AUTH": "redis://redis:6379/1"},
}
for name, kv in files.items():
    path = out / name
    path.write_text("".join(f"{k}={v}\n" for k, v in kv.items()))
    path.chmod(0o600)
print(f"wrote {', '.join(files)} to {out}")
