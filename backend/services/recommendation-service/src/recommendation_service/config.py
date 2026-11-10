from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="RECO_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    eligibility_url: str = "http://eligibility-service:8005"
    retrieval_url: str = "http://retrieval-service:8004"
    llm_gateway_url: str = "http://llm-gateway:8001"

    # Model ALIASES only; the vendor/model behind them is llm-gateway's business.
    llm_alias: str = "recommender"
    translate_alias: str = "translate"

    prompt_version: str = "v2"  # see prompts/README.md; v1 = long prompt, v2 = compact prompt for <=3B models
    explain_prompt_version: str = "v1"
    # Languages the LLM writes directly. Others are generated in `pivot_language`, then translated via the
    # "translate" alias (a <=3B model is weak in low-resource languages).
    direct_languages: str = "en,hi"
    pivot_language: str = "en"
    # Token estimate = chars / 4. Small local models have small windows (~4k): keep the docs budget low.
    context_token_budget: int = 3000
    retrieval_top_k: int = 30
    chunks_per_scheme: int = 2
    llm_max_tokens: int = 1024
    llm_temperature: float = 0.2

    # time limits (seconds)
    dependency_timeout: float = 15.0
    llm_timeout: float = 90.0
    request_deadline: float = 120.0

    # circuit breaker per downstream service: open after N consecutive failures, retry after `reset` seconds
    breaker_threshold: int = 5
    breaker_reset: float = 30.0

    # public-API hardening
    max_body_bytes: int = 16384
    metrics_token: str = ""  # if set, GET /metrics requires "Authorization: Bearer <token>"

    # shared state for horizontal scaling (cache + rate limits). Empty = in-memory, single replica only.
    redis_url: str = ""

    # end-user authentication: tokens from auth-service, verified with its JWKS (no shared secret)
    auth_mode: str = "optional"  # off | optional (anonymous allowed, tokens verified if sent) | required
    auth_jwks_url: str = "http://auth-service:8006/.well-known/jwks.json"
    auth_issuer: str = "adhikar-auth"
    auth_audience: str = "adhikar-api"

    cache_ttl: int = 120
    cache_max: int = 1000

    cors_origins: str = "*"  # comma-separated list of allowed origins
    rate_limit_per_minute: int = 60  # anonymous clients, per IP
    rate_limit_per_minute_user: int = 120  # signed-in users, per account
    trust_forwarded_for: bool = False  # only behind a reverse proxy you control that sets X-Forwarded-For
    admin_token: str = ""  # enables POST /v1/admin/cache/clear (Bearer token); empty = endpoint disabled
    max_more: int = 20  # cap for the "more" list


def get_settings() -> Settings:
    return Settings()
