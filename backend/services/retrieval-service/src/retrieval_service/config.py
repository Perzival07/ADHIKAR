from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="RETRIEVAL_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    qdrant_url: str = "http://qdrant:6333"  # ":memory:" for tests
    qdrant_api_key: str = ""
    embedding_url: str = "http://embedding-service:8002"
    collection_prefix: str = "scheme_chunks"
    request_timeout: float = 30.0
    breaker_threshold: int = 5
    breaker_reset: float = 30.0

    # candidate pool per leg (semantic / keyword) before fusion
    pool: int = 100
    # keyword leg scans at most this many filtered chunks
    keyword_scan_limit: int = 8000
    # Reciprocal Rank Fusion: score = w / (rrf_k + rank)
    rrf_k: int = 60
    weight_semantic: float = 1.0
    weight_keyword: float = 1.0

    # Optional reranker (OFF by default). "llm" re-scores the fused top candidates through llm-gateway.
    reranker: str = "none"  # none | llm
    llm_gateway_url: str = "http://llm-gateway:8001"
    reranker_alias: str = "reranker"
    rerank_candidates: int = 20


def get_settings() -> Settings:
    return Settings()
