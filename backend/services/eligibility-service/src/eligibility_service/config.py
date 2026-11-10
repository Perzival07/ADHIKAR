from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ELIG_", env_file=".env", extra="ignore")

    log_level: str = "INFO"
    docs_dir: str = "../../data/scheme_docs"


def get_settings() -> Settings:
    return Settings()
