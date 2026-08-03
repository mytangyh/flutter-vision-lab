import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import ValidationError

from app.main import app, get_provider, get_settings
from app.provider import Recognition, RecognitionUsage
from app.settings import Settings


TEST_CLIENT_TOKEN = "test-client-token-at-least-32-characters"


@pytest.fixture(autouse=True)
def configured_settings():  # type: ignore[no-untyped-def]
    app.dependency_overrides[get_settings] = lambda: Settings(
        client_token=TEST_CLIENT_TOKEN,
    )
    yield
    app.dependency_overrides.clear()


class FakeProvider:
    async def recognize(self, **_: object) -> Recognition:
        return Recognition(
            name="马克杯",
            brand="测试品牌",
            description="一个白色陶瓷杯",
            provider="fake",
            model="fake-vlm",
            usage=RecognitionUsage(prompt_tokens=10, completion_tokens=5),
        )


def jpeg() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (32, 32), "white").save(output, "JPEG")
    return output.getvalue()


def test_health() -> None:
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.json()["status"] == "ok"
    assert response.json()["vlm_configured"] is False
    assert response.json()["vlm_model"] == "doubao-seed-2-1-pro-260628"
    assert response.headers["content-type"] == "application/json; charset=utf-8"


def test_settings_require_client_token(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CLIENT_TOKEN", raising=False)
    with pytest.raises(ValidationError):
        Settings(_env_file=None)


def test_recognition_contract() -> None:
    app.dependency_overrides[get_provider] = lambda: FakeProvider()
    try:
        with TestClient(app) as client:
            response = client.post(
                "/api/v1/recognitions",
                files={"image": ("target.jpg", jpeg(), "image/jpeg")},
                data={
                    "request_id": "request-1",
                    "track_id": "track-1",
                    "coarse_label": "cup",
                    "coarse_confidence": "0.87",
                    "locale": "zh-CN",
                },
                headers={"X-Client-Token": TEST_CLIENT_TOKEN},
            )
    finally:
        app.dependency_overrides.pop(get_provider, None)
    assert response.status_code == 200
    assert response.json()["name"] == "马克杯"
    assert response.json()["brand"] == "测试品牌"
    assert response.json()["provider"] == "fake"
    assert response.json()["usage"]["prompt_tokens"] == 10


def test_recognition_requires_client_token() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/recognitions",
            files={"image": ("target.jpg", jpeg(), "image/jpeg")},
            data={
                "request_id": "request-unauthorized",
                "track_id": "track-unauthorized",
                "coarse_label": "cup",
                "coarse_confidence": "0.87",
            },
        )
    assert response.status_code == 401


def test_rejects_non_image() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/recognitions",
            files={"image": ("bad.txt", b"not-an-image", "text/plain")},
            data={
                "request_id": "request-2",
                "track_id": "track-2",
                "coarse_label": "book",
                "coarse_confidence": "0.6",
            },
            headers={"X-Client-Token": TEST_CLIENT_TOKEN},
        )
    assert response.status_code == 415


def test_rejects_oversized_dimensions() -> None:
    output = io.BytesIO()
    Image.new("RGB", (4097, 8), "white").save(output, "PNG")
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/recognitions",
            files={"image": ("wide.png", output.getvalue(), "image/png")},
            data={
                "request_id": "request-3",
                "track_id": "track-3",
                "coarse_label": "book",
                "coarse_confidence": "0.6",
            },
            headers={"X-Client-Token": TEST_CLIENT_TOKEN},
        )
    assert response.status_code == 422
