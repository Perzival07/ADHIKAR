from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="EMBED_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    provider: str = "hash"  # hash | sentence_transformers | ollama
    batch_size: int = 32
    # Inputs longer than this are truncated AND flagged in the response (never silently).
    max_input_chars: int = 4000

    # hash provider (dev/test default; deterministic, offline)
    hash_dim: int = 384

    # sentence_transformers provider: a LOCAL model folder; never auto-downloaded.
    model_path: str = ""
    device: str = "cpu"  # keep the GPU free for the LLM
    query_prefix: str = ""  # e.g. "query: " for e5-style models
    document_prefix: str = ""  # e.g. "passage: " for e5-style models

    # ollama provider
    ollama_base_url: str = "http://host.docker.internal:11434"
    ollama_model: str = ""
    timeout: float = 60.0


def get_settings() -> Settings:
    return Settings()
