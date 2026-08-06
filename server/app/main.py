import json
import logging
import re
import secrets
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Annotated, AsyncIterator

import httpx
from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Request,
    UploadFile,
)
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from .images import InvalidImageError, normalize_image
from .limits import ConcurrencyLimiter, SlidingWindowRateLimiter
from .provider import (
    OpenAICompatibleProvider,
    ProviderRequestError,
    ProviderResponseError,
)
from .settings import Settings, get_settings

logger = logging.getLogger("aicamera.server")
request_id_pattern = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class Utf8JsonResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


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


@dataclass
class Runtime:
    settings: Settings
    provider: OpenAICompatibleProvider
    rate_limiter: SlidingWindowRateLimiter
    concurrency_limiter: ConcurrencyLimiter


def create_app(
    *,
    settings: Settings | None = None,
    provider: OpenAICompatibleProvider | None = None,
    http_client: httpx.AsyncClient | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        active_settings = settings or get_settings()
        owns_client = http_client is None
        active_client = http_client or httpx.AsyncClient(
            timeout=httpx.Timeout(
                active_settings.request_timeout_seconds,
                connect=active_settings.connect_timeout_seconds,
            ),
            limits=httpx.Limits(
                max_connections=active_settings.max_concurrent_requests,
                max_keepalive_connections=active_settings.max_concurrent_requests,
                keepalive_expiry=30,
            ),
            follow_redirects=False,
            trust_env=active_settings.http_trust_env,
        )
        app.state.runtime = Runtime(
            settings=active_settings,
            provider=provider
            or OpenAICompatibleProvider(active_settings, active_client),
            rate_limiter=SlidingWindowRateLimiter(
                max_requests=active_settings.rate_limit_requests,
                window_seconds=active_settings.rate_limit_window_seconds,
            ),
            concurrency_limiter=ConcurrencyLimiter(
                active_settings.max_concurrent_requests
            ),
        )
        logger.info(
            json.dumps(
                {
                    "event": "server_started",
                    "model": active_settings.vlm_model,
                    "max_concurrent_requests": active_settings.max_concurrent_requests,
                    "rate_limit_requests": active_settings.rate_limit_requests,
                    "rate_limit_window_seconds": active_settings.rate_limit_window_seconds,
                },
                ensure_ascii=False,
            )
        )
        try:
            yield
        finally:
            if owns_client:
                await active_client.aclose()

    app = FastAPI(
        title="Flutter Vision Lab Cloud Recognition Proxy",
        version="0.2.0",
        default_response_class=Utf8JsonResponse,
        lifespan=lifespan,
    )

    @app.middleware("http")
    async def request_logging(
        request: Request,
        call_next,
    ):  # type: ignore[no-untyped-def]
        supplied_id = request.headers.get("X-Request-ID", "")
        trace_id = (
            supplied_id
            if request_id_pattern.fullmatch(supplied_id)
            else uuid.uuid4().hex
        )
        request.state.trace_id = trace_id
        started = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            response.headers["X-Request-ID"] = trace_id
            return response
        finally:
            logger.info(
                json.dumps(
                    {
                        "event": "http_request",
                        "request_id": trace_id,
                        "method": request.method,
                        "path": request.url.path,
                        "status_code": status_code,
                        "latency_ms": round(
                            (time.perf_counter() - started) * 1000
                        ),
                    },
                    ensure_ascii=False,
                )
            )

    @app.get("/health/live")
    async def health_live() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/health/ready")
    async def health_ready(
        runtime: Annotated[Runtime, Depends(get_runtime)],
    ) -> dict[str, str | bool]:
        return {
            "status": "ready",
            "vlm_configured": True,
            "vlm_model": runtime.settings.vlm_model,
        }

    @app.get("/health")
    async def health(
        runtime: Annotated[Runtime, Depends(get_runtime)],
    ) -> dict[str, str | bool]:
        return {
            "status": "ready",
            "vlm_configured": True,
            "vlm_model": runtime.settings.vlm_model,
        }

    @app.post("/api/v1/recognitions", response_model=RecognitionResponse)
    async def recognize(
        request: Request,
        image: Annotated[UploadFile, File()],
        request_id: Annotated[str, Form(min_length=1, max_length=128)],
        track_id: Annotated[str, Form(min_length=1, max_length=128)],
        coarse_label: Annotated[
            str,
            Form(min_length=1, max_length=80, pattern=r"^[^\r\n\x00-\x1f\x7f]+$"),
        ],
        coarse_confidence: Annotated[float, Form(ge=0, le=1)],
        runtime: Annotated[Runtime, Depends(get_runtime)],
        locale: Annotated[
            str,
            Form(pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$"),
        ] = "zh-CN",
        x_client_token: Annotated[str | None, Header()] = None,
    ) -> RecognitionResponse:
        if x_client_token is None or not secrets.compare_digest(
            x_client_token,
            runtime.settings.expected_client_token,
        ):
            raise HTTPException(status_code=401, detail="Invalid client token.")

        client_host = request.client.host if request.client else "unknown"
        allowed, retry_after = await runtime.rate_limiter.allow(client_host)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded.",
                headers={"Retry-After": str(retry_after)},
            )
        if not await runtime.concurrency_limiter.try_acquire():
            raise HTTPException(
                status_code=503,
                detail="Server is busy.",
                headers={"Retry-After": "1"},
            )

        try:
            return await _recognize(
                image=image,
                request_id=request_id,
                track_id=track_id,
                coarse_label=coarse_label,
                coarse_confidence=coarse_confidence,
                locale=locale,
                runtime=runtime,
                trace_id=request.state.trace_id,
            )
        finally:
            await runtime.concurrency_limiter.release()

    return app


def get_runtime(request: Request) -> Runtime:
    return request.app.state.runtime


async def _recognize(
    *,
    image: UploadFile,
    request_id: str,
    track_id: str,
    coarse_label: str,
    coarse_confidence: float,
    locale: str,
    runtime: Runtime,
    trace_id: str,
) -> RecognitionResponse:
    settings = runtime.settings
    image_bytes = await image.read(settings.max_image_bytes + 1)
    if len(image_bytes) > settings.max_image_bytes:
        raise HTTPException(status_code=413, detail="Image is too large.")
    try:
        normalized = await run_in_threadpool(
            normalize_image,
            image_bytes,
            max_dimension=settings.max_image_dimension,
        )
    except InvalidImageError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    started = time.perf_counter()
    try:
        result = await runtime.provider.recognize(
            image=normalized.data,
            mime_type=normalized.mime_type,
            coarse_label=coarse_label,
            coarse_confidence=coarse_confidence,
            locale=locale,
        )
    except ProviderRequestError as error:
        logger.warning(
            json.dumps(
                {
                    "event": "provider_request_failed",
                    "request_id": trace_id,
                    "error_type": type(error).__name__,
                }
            )
        )
        raise HTTPException(status_code=502, detail="VLM request failed.") from error
    except ProviderResponseError as error:
        logger.warning(
            json.dumps(
                {
                    "event": "provider_response_invalid",
                    "request_id": trace_id,
                    "error_type": type(error).__name__,
                }
            )
        )
        raise HTTPException(status_code=502, detail="VLM response was invalid.") from error

    latency_ms = round((time.perf_counter() - started) * 1000)
    logger.info(
        json.dumps(
            {
                "event": "recognition_completed",
                "request_id": trace_id,
                "client_request_id": request_id,
                "track_id": track_id,
                "model": result.model,
                "latency_ms": latency_ms,
                "prompt_tokens": result.usage.prompt_tokens,
                "completion_tokens": result.usage.completion_tokens,
                "reasoning_tokens": result.usage.reasoning_tokens,
            },
            ensure_ascii=False,
        )
    )
    return RecognitionResponse(
        request_id=request_id,
        track_id=track_id,
        name=result.name,
        brand=result.brand,
        description=result.description,
        provider=result.provider,
        model=result.model,
        latency_ms=latency_ms,
        usage=UsageResponse(
            prompt_tokens=result.usage.prompt_tokens,
            completion_tokens=result.usage.completion_tokens,
            reasoning_tokens=result.usage.reasoning_tokens,
        ),
    )


app = create_app()
