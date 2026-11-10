import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from haqdaar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    setup_json_logging,
)
from sse_starlette.sse import EventSourceResponse

from .config import Settings, get_settings
from .contract_models import ChatRequest, ChatResponse, ModelsResponse
from .errors import GatewayError
from .gateway import Gateway
from .registry import Registry as ProviderRegistry

SERVICE = "llm-gateway"
log = logging.getLogger("llm_gateway")


def create_app(settings: Settings | None = None, transport=None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    registry = ProviderRegistry.from_file(settings.models_file, settings, transport)
    metrics_registry = Registry()
    gateway = Gateway(registry, settings, metrics_registry)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        await registry.aclose()

    app = FastAPI(title=SERVICE, version="0.1.0", separate_input_output_schemas=False, lifespan=lifespan)
    install_metrics(app, SERVICE, metrics_registry)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.gateway = gateway
    app.state.metrics = metrics_registry

    @app.exception_handler(GatewayError)
    async def gateway_error(_: Request, exc: GatewayError):
        body = {"detail": exc.message, **exc.extra}
        return JSONResponse(body, status_code=exc.status_code)

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        per_alias = await gateway.health()
        ok = all(per_alias.values())
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": per_alias}, status_code=200 if ok else 503)

    @app.post("/v1/chat", response_model=ChatResponse, response_model_by_alias=True)
    async def chat(req: ChatRequest):
        if req.stream:
            registry.get(req.model_alias)  # 404 before opening the stream

            async def events():
                try:
                    async for ev in gateway.stream(req):
                        if "delta" in ev:
                            yield {"data": json.dumps(ev, ensure_ascii=False)}
                        else:
                            yield {"event": "done", "data": json.dumps(ev["done"])}
                except GatewayError as e:
                    yield {"event": "error", "data": json.dumps({"detail": e.message, "status": e.status_code})}

            return EventSourceResponse(events())
        return await gateway.chat(req)

    @app.get("/v1/models", response_model=ModelsResponse)
    async def models():
        return ModelsResponse(aliases=gateway.models())

    return app


def app_factory():  # uvicorn --factory <pkg>.main:app_factory (no app is built at import time)
    return create_app()
