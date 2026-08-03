import asyncio
import json

import httpx

from app.provider import OpenAICompatibleProvider
from app.settings import Settings


def test_provider_disables_thinking_and_normalizes_usage(monkeypatch) -> None:
    captured: dict[str, object] = {}

    async def fake_post(self, url, *, headers, json):  # type: ignore[no-untyped-def]
        captured["url"] = url
        captured["headers"] = headers
        captured["payload"] = json
        return httpx.Response(
            200,
            request=httpx.Request("POST", url),
            json={
                "choices": [
                    {
                        "message": {
                            "content": json_module.dumps(
                                {
                                    "name": "棉柔亲肤抽纸",
                                    "brand": "清风",
                                    "description": "4层加厚升级",
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ],
                "usage": {
                    "prompt_tokens": 243,
                    "completion_tokens": 31,
                    "completion_tokens_details": {"reasoning_tokens": 0},
                },
            },
        )

    json_module = json
    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    provider = OpenAICompatibleProvider(
        Settings(
            vlm_base_url="https://vlm.example.com/v1",
            vlm_api_key="server-secret",
            client_token="test-client-token-at-least-32-characters",
        )
    )

    result = asyncio.run(
        provider.recognize(
            image=b"jpeg",
            mime_type="image/jpeg",
            coarse_label="book",
            coarse_confidence=0.8,
            locale="zh-CN",
        )
    )

    assert captured["url"] == "https://vlm.example.com/v1/chat/completions"
    payload = captured["payload"]
    assert isinstance(payload, dict)
    assert payload["model"] == "doubao-seed-2-1-pro-260628"
    assert payload["thinking"] == {"type": "disabled"}
    assert "server-secret" not in str(payload)
    assert result.name == "棉柔亲肤抽纸"
    assert result.brand == "清风"
    assert result.usage.prompt_tokens == 243
