import base64
import json
from dataclasses import dataclass

import httpx

from .settings import Settings


@dataclass(frozen=True)
class RecognitionUsage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    reasoning_tokens: int = 0


@dataclass(frozen=True)
class Recognition:
    name: str
    brand: str | None
    description: str
    provider: str
    model: str
    usage: RecognitionUsage = RecognitionUsage()


class OpenAICompatibleProvider:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def recognize(
        self,
        *,
        image: bytes,
        mime_type: str,
        coarse_label: str,
        coarse_confidence: float,
        locale: str,
    ) -> Recognition:
        settings = self._settings
        if not (
            settings.vlm_base_url
            and settings.vlm_api_key
            and settings.vlm_model
        ):
            raise ProviderConfigurationError(
                "VLM_BASE_URL, VLM_API_KEY and VLM_MODEL must be configured."
            )

        encoded = base64.b64encode(image).decode("ascii")
        prompt = (
            "Identify the main object in this cropped image. "
            f"The local detector guessed '{coarse_label}' with confidence "
            f"{coarse_confidence:.3f}; this hint may be wrong. "
            f"Respond in locale {locale}. Return compact JSON only with string "
            "fields name, brand and description. Use null for brand when it is "
            "not clearly visible. Describe only visible or strongly supported "
            "attributes. Do not guess a brand, model, material or specification."
        )
        payload = {
            "model": settings.vlm_model,
            "temperature": 0,
            "max_tokens": settings.vlm_max_tokens,
            "response_format": {"type": "json_object"},
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{mime_type};base64,{encoded}",
                                "detail": settings.vlm_image_detail,
                            },
                        },
                    ],
                }
            ],
        }
        if settings.vlm_disable_thinking:
            payload["thinking"] = {"type": "disabled"}
        url = f"{settings.vlm_base_url.rstrip('/')}/chat/completions"
        try:
            async with httpx.AsyncClient(
                timeout=settings.request_timeout_seconds
            ) as client:
                response = await client.post(
                    url,
                    headers={
                        "Authorization": f"Bearer {settings.vlm_api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                response.raise_for_status()
        except httpx.HTTPError as error:
            raise ProviderRequestError(str(error)) from error

        try:
            upstream = response.json()
            content = upstream["choices"][0]["message"]["content"]
            parsed = json.loads(_extract_json_object(content))
            name = str(parsed["name"]).strip()
            description = str(parsed["description"]).strip()
            if not name or not description:
                raise ValueError("empty recognition field")
            brand = _optional_text(parsed.get("brand"))
            usage = upstream.get("usage") or {}
            completion_details = usage.get("completion_tokens_details") or {}
            recognition_usage = RecognitionUsage(
                prompt_tokens=_non_negative_int(usage.get("prompt_tokens")),
                completion_tokens=_non_negative_int(usage.get("completion_tokens")),
                reasoning_tokens=_non_negative_int(
                    completion_details.get("reasoning_tokens")
                ),
            )
        except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise ProviderResponseError("VLM returned an invalid JSON response.") from error

        return Recognition(
            name=name[:80],
            brand=brand[:80] if brand else None,
            description=description[:240],
            provider="openai-compatible",
            model=settings.vlm_model,
            usage=recognition_usage,
        )


def _extract_json_object(content: object) -> str:
    if not isinstance(content, str):
        raise TypeError("VLM content must be text")
    text = content.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].strip().lower() in {"```", "```json"}:
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        raise ValueError("VLM content does not contain a JSON object")
    return text[start : end + 1]


def _optional_text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if text.lower() in {"", "unknown", "null", "none", "n/a"} or text in {
        "未知",
        "不确定",
    }:
        return None
    return text


def _non_negative_int(value: object) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


class ProviderConfigurationError(RuntimeError):
    pass


class ProviderRequestError(RuntimeError):
    pass


class ProviderResponseError(RuntimeError):
    pass
