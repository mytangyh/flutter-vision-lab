from functools import lru_cache
from typing import Literal

from pydantic import AnyHttpUrl, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    vlm_base_url: AnyHttpUrl
    vlm_api_key: SecretStr
    vlm_model: str = Field(min_length=1, max_length=128)
    vlm_disable_thinking: bool = True
    vlm_image_detail: Literal["low", "high", "auto"] = "low"
    vlm_max_tokens: int = Field(default=160, ge=1, le=4096)
    client_token: SecretStr

    allow_http_upstream: bool = False
    http_trust_env: bool = False
    connect_timeout_seconds: float = Field(default=5, ge=0.1, le=30)
    request_timeout_seconds: float = Field(default=20, ge=1, le=120)
    upstream_max_attempts: int = Field(default=2, ge=1, le=4)
    upstream_retry_base_seconds: float = Field(default=0.5, ge=0.05, le=5)
    upstream_max_response_bytes: int = Field(
        default=1024 * 1024,
        ge=16 * 1024,
        le=4 * 1024 * 1024,
    )

    max_image_bytes: int = Field(
        default=2 * 1024 * 1024,
        ge=64 * 1024,
        le=10 * 1024 * 1024,
    )
    max_image_dimension: int = Field(default=4096, ge=64, le=8192)
    max_concurrent_requests: int = Field(default=4, ge=1, le=32)
    rate_limit_requests: int = Field(default=30, ge=1, le=1000)
    rate_limit_window_seconds: int = Field(default=60, ge=1, le=3600)

    @field_validator("vlm_api_key", mode="before")
    @classmethod
    def validate_api_key(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        if value != value.strip() or any(character.isspace() for character in value):
            raise ValueError("Secrets must not contain whitespace.")
        if len(value) < 8:
            raise ValueError("VLM_API_KEY must contain at least 8 characters.")
        return value

    @field_validator("client_token", mode="before")
    @classmethod
    def validate_client_token(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        if value != value.strip() or any(character.isspace() for character in value):
            raise ValueError("Secrets must not contain whitespace.")
        if len(value) < 32:
            raise ValueError("CLIENT_TOKEN must contain at least 32 characters.")
        return value

    @field_validator("vlm_model")
    @classmethod
    def validate_model(cls, value: str) -> str:
        model = value.strip()
        if not model or any(character in model for character in "\r\n"):
            raise ValueError("VLM_MODEL must be a non-empty single line.")
        return model

    @model_validator(mode="after")
    def validate_upstream_scheme(self) -> "Settings":
        if self.vlm_base_url.scheme != "https" and not self.allow_http_upstream:
            raise ValueError(
                "VLM_BASE_URL must use HTTPS unless ALLOW_HTTP_UPSTREAM=true."
            )
        if (
            self.vlm_base_url.username
            or self.vlm_base_url.password
            or self.vlm_base_url.query
            or self.vlm_base_url.fragment
        ):
            raise ValueError(
                "VLM_BASE_URL must not contain credentials, query parameters or fragments."
            )
        return self

    @property
    def upstream_api_key(self) -> str:
        return self.vlm_api_key.get_secret_value()

    @property
    def expected_client_token(self) -> str:
        return self.client_token.get_secret_value()


@lru_cache
def get_settings() -> Settings:
    return Settings()
