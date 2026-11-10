from __future__ import annotations

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ConfigError(RuntimeError):
    pass


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AUTH_", env_file=".env", extra="ignore")

    env: str = "development"  # development | production
    log_level: str = "INFO"
    database_url: str = "sqlite+aiosqlite:///./auth-dev.db"
    redis_url: str = ""  # shared rate limits across replicas (empty = in-memory)

    # JWT (ES256). PEM private key; in development an ephemeral key is generated if empty.
    jwt_private_key: str = ""
    jwt_issuer: str = "haqdaar-auth"
    jwt_audience: str = "haqdaar-api"
    access_token_ttl: int = 900  # 15 min
    refresh_token_ttl: int = 30 * 24 * 3600  # 30 days

    # OTP
    otp_secret: str = ""  # HMAC pepper for stored OTP codes; required in production
    otp_ttl: int = 300
    otp_attempts: int = 5
    otp_resend_cooldown: int = 60
    otp_max_per_hour: int = 5

    # passwords / lockout
    password_min_length: int = 8
    max_failed_logins: int = 5
    lockout_seconds: int = 900

    # per-IP request limits on auth endpoints
    rate_limit_per_minute: int = 30
    trust_forwarded_for: bool = False

    # email delivery: console (development only) | smtp
    email_backend: str = "console"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from: str = "Haqdaar <no-reply@haqdaar.example>"
    smtp_starttls: bool = True

    cors_origins: str = ""
    seed_demo_users: bool = False  # development convenience only

    @property
    def is_production(self) -> bool:
        return self.env.lower() == "production"

    @model_validator(mode="after")
    def _production_guardrails(self) -> Settings:
        if not self.is_production:
            return self
        problems = []
        if not self.jwt_private_key:
            problems.append("AUTH_JWT_PRIVATE_KEY must be set")
        if len(self.otp_secret) < 32:
            problems.append("AUTH_OTP_SECRET must be at least 32 characters")
        if self.email_backend == "console":
            problems.append("AUTH_EMAIL_BACKEND=console would log OTP codes; use smtp")
        if self.database_url.startswith("sqlite"):
            problems.append("AUTH_DATABASE_URL must point to Postgres")
        if self.seed_demo_users:
            problems.append("AUTH_SEED_DEMO_USERS must be false")
        if self.cors_origins.strip() == "*":
            problems.append("AUTH_CORS_ORIGINS must list explicit origins")
        if problems:
            raise ConfigError("refusing to start in production: " + "; ".join(problems))
        return self


def get_settings() -> Settings:
    return Settings()
