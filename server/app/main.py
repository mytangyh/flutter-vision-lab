import io
import secrets
import time
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel

from .provider import (
    OpenAICompatibleProvider,
    ProviderConfigurationError,
    ProviderRequestError,
    ProviderResponseError,
)
from .settings import Settings, get_settings

class Utf8JsonResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


app = FastAPI(
    title="AICAMERA Cloud Recognition Proxy",
    version="0.1.0",
    default_response_class=Utf8JsonResponse,
)


class UsageResponse(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    reasoning_tokens: int


class RecognitionResponse(BaseModel):
    request_id: str
    track_id: str
    name: str
    brand: str | None
    description: str
    provider: str
    model: str
    latency_ms: int
    usage: UsageResponse


def get_provider(
    settings: Annotated[Settings, Depends(get_settings)],
) -> OpenAICompatibleProvider:
    return OpenAICompatibleProvider(settings)


@app.get("/health")
async def health(
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, str | bool]:
    return {
        "status": "ok",
        "vlm_configured": bool(settings.vlm_api_key),
        "vlm_model": settings.vlm_model,
    }


@app.post("/api/v1/recognitions", response_model=RecognitionResponse)
async def recognize(
    image: Annotated[UploadFile, File()],
    request_id: Annotated[str, Form(min_length=1, max_length=128)],
    track_id: Annotated[str, Form(min_length=1, max_length=128)],
    coarse_label: Annotated[str, Form(min_length=1, max_length=80)],
    coarse_confidence: Annotated[float, Form(ge=0, le=1)],
    settings: Annotated[Settings, Depends(get_settings)],
    provider: Annotated[OpenAICompatibleProvider, Depends(get_provider)],
    locale: Annotated[str, Form(max_length=20)] = "zh-CN",
    x_client_token: Annotated[str | None, Header()] = None,
) -> RecognitionResponse:
    if x_client_token is None or not secrets.compare_digest(
        x_client_token,
        settings.client_token,
    ):
        raise HTTPException(status_code=401, detail="Invalid client token.")
    if image.content_type not in {"image/jpeg", "image/png"}:
        raise HTTPException(status_code=415, detail="Only JPEG and PNG are supported.")

    image_bytes = await image.read(settings.max_image_bytes + 1)
    if len(image_bytes) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail="Image is too large.")
    try:
        with Image.open(io.BytesIO(image_bytes)) as decoded:
            decoded.verify()
            if decoded.width < 8 or decoded.height < 8:
                raise HTTPException(status_code=422, detail="Image is too small.")
            if (
                decoded.width > settings.max_image_dimension
                or decoded.height > settings.max_image_dimension
            ):
                raise HTTPException(status_code=422, detail="Image dimensions are too large.")
    except (UnidentifiedImageError, OSError) as error:
        raise HTTPException(status_code=422, detail="Invalid image.") from error

    started = time.perf_counter()
    try:
        result = await provider.recognize(
            image=image_bytes,
            mime_type=image.content_type,
            coarse_label=coarse_label,
            coarse_confidence=coarse_confidence,
            locale=locale,
        )
    except ProviderConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ProviderRequestError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
    except ProviderResponseError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    return RecognitionResponse(
        request_id=request_id,
        track_id=track_id,
        name=result.name,
        brand=result.brand,
        description=result.description,
        provider=result.provider,
        model=result.model,
        latency_ms=round((time.perf_counter() - started) * 1000),
        usage=UsageResponse(
            prompt_tokens=result.usage.prompt_tokens,
            completion_tokens=result.usage.completion_tokens,
            reasoning_tokens=result.usage.reasoning_tokens,
        ),
    )
