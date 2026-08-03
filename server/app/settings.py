from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    vlm_base_url: str = ""
    vlm_api_key: str = ""
    vlm_model: str = "doubao-seed-2-1-pro-260628"
    vlm_disable_thinking: bool = True
    vlm_image_detail: str = "low"
    vlm_max_tokens: int = 160
    client_token: str = Field(min_length=32)
    request_timeout_seconds: float = 20
    max_image_bytes: int = 2 * 1024 * 1024
    max_image_dimension: int = 4096


@lru_cache
def get_settings() -> Settings:
    return Settings()
