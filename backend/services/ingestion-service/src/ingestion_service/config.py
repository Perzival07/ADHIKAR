from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="INGEST_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    docs_dir: str = "../../data/scheme_docs"
    state_dir: str = "./.state"  # sqlite manifest lives here (a volume in docker)
    qdrant_url: str = "http://qdrant:6333"  # ":memory:" for tests
    qdrant_api_key: str = ""
    embedding_url: str = "http://embedding-service:8002"
    collection_prefix: str = "scheme_chunks"
    # Token estimate = chars / 4. Chunks target ~chunk_tokens with chunk_overlap tokens of overlap.
    chunk_tokens: int = 550
    chunk_overlap: int = 80
    embed_batch: int = 32
    request_timeout: float = 60.0
    watch: bool = False
    # After a run that changed the index, ask recommendation-service to drop cached answers (optional).
    cache_clear_url: str = ""  # e.g. http://recommendation-service:8000/v1/admin/cache/clear
    cache_clear_token: str = ""


def get_settings() -> Settings:
    return Settings()
