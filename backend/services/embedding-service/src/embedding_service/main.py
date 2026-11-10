import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from haqdaar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    setup_json_logging,
)

from .config import Settings, get_settings
from .contract_models import EmbedRequest, EmbedResponse
from .providers import build_provider
from .providers.ollama_provider import EmbeddingUnavailable

SERVICE = "embedding-service"
log = logging.getLogger("embedding_service")


def create_app(settings: Settings | None = None, transport=None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    provider = build_provider(settings, transport)
    metrics = Registry()
    m_texts = metrics.counter("embed_texts_total", "Texts embedded", ("kind",))
    m_trunc = metrics.counter("embed_truncated_total", "Inputs truncated to the length cap", ())
    m_fail = metrics.counter("embed_failures_total", "Embedding failures", ())

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        await provider.aclose()

    app = FastAPI(title=SERVICE, version="0.1.0", separate_input_output_schemas=False, lifespan=lifespan)
    install_metrics(app, SERVICE, metrics)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.metrics = metrics

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        ok, msg = await provider.ready()
        body = {"ready": ok, "service": SERVICE, "checks": {settings.provider: msg}}
        return JSONResponse(body, status_code=200 if ok else 503)

    @app.post("/v1/embed", response_model=EmbedResponse)
    async def embed(req: EmbedRequest):
        cap = settings.max_input_chars
        truncated = [len(t) > cap for t in req.texts]  # explicit flags, never silent
        texts = [t[:cap] for t in req.texts]
        vectors: list[list[float]] = []
        try:
            for i in range(0, len(texts), max(1, settings.batch_size)):
                vectors.extend(await provider.embed(texts[i : i + settings.batch_size], req.kind))
            model_id, dim = await provider.info()
        except (EmbeddingUnavailable, RuntimeError) as e:
            m_fail.inc()
            raise HTTPException(503, str(e)) from e
        m_texts.inc(len(texts), kind=req.kind)
        m_trunc.inc(sum(truncated))
        return EmbedResponse(vectors=vectors, dim=dim, model_id=model_id, truncated=truncated)

    return app


def app_factory():  # uvicorn --factory <pkg>.main:app_factory (no app is built at import time)
    return create_app()
