from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="LLMGW_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    models_file: str = "models.yaml"
    # Concurrent generations allowed. 1 = a single local GPU is never overloaded.
    concurrency: int = 1
    # Requests allowed to wait for a slot; beyond this -> 429 (caller falls back to rules-only).
    queue_max: int = 8
    connect_timeout: float = 5.0
    read_timeout: float = 120.0
    ollama_base_url: str = "http://host.docker.internal:11434"
    # Message content is only ever logged at DEBUG and only when this flag is on.
    log_content: bool = False


def get_settings() -> Settings:
    return Settings()
