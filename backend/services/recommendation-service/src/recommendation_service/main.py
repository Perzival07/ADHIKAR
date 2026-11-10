import asyncio
import hmac
import json
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from haqdaar_common import (
    AccessLogMiddleware,
    JWKSVerifier,
    Principal,
    Registry,
    RequestIDMiddleware,
    TokenInvalid,
    install_metrics,
    make_cache,
    make_rate_limiter,
    make_redis,
    setup_json_logging,
)
from sse_starlette.sse import EventSourceResponse

from .clients import Clients, DependencyError
from .config import Settings, get_settings
from .contract_models import ExplainRequest, ExplainResponse, RecommendationRequest, RecommendationResponse
from .limits import BodySizeLimitMiddleware
from .metrics import Metrics
from .pipeline import Pipeline
from .ratelimit import client_key

SERVICE = "recommendation-service"
log = logging.getLogger("recommendation_service")
AUTH_MODES = {"off", "optional", "required"}


def create_app(settings: Settings | None = None, transport=None, redis=None, jwks_transport=None) -> FastAPI:
    settings = settings or get_settings()
    if settings.auth_mode not in AUTH_MODES:
        raise ValueError(f"RECO_AUTH_MODE must be one of {sorted(AUTH_MODES)}")
    setup_json_logging(SERVICE, settings.log_level)
    registry = Registry()
    metrics = Metrics(registry)
    redis = redis if redis is not None else make_redis(settings.redis_url)
    clients = Clients(settings, transport, on_circuit_open=lambda name: metrics.inc("circuit_open_total"))
    pipeline = Pipeline(settings, clients, make_cache(redis, "reco:cache", settings.cache_max), metrics)
    limiter = make_rate_limiter(redis, "reco:rl")
    verifier = None
    if settings.auth_mode != "off":
        verifier = JWKSVerifier(settings.auth_jwks_url, settings.auth_issuer, settings.auth_audience,
                                httpx.AsyncClient(timeout=5.0, transport=jwks_transport or transport))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        await clients.aclose()
        if verifier:
            await verifier.client.aclose()
        if redis is not None:
            try:
                await redis.aclose()
            except Exception:  # noqa: BLE001 - shutting down; Redis may already be gone
                log.warning("redis close failed during shutdown")

    app = FastAPI(title=SERVICE, version="1.0.0", separate_input_output_schemas=False, lifespan=lifespan)
    # add_middleware order: last added runs first. Request id must wrap everything.
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST"],
                       allow_headers=["authorization", "content-type", "x-request-id", "cache-control"],
                       expose_headers=["X-Request-ID", "Retry-After"])
    app.add_middleware(BodySizeLimitMiddleware, max_bytes=settings.max_body_bytes)
    install_metrics(app, SERVICE, registry, token=settings.metrics_token)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.pipeline = pipeline
    app.state.metrics = metrics
    app.state.limiter = limiter

    async def edge_guard(request: Request) -> Principal | None:
        """Authenticate (per RECO_AUTH_MODE) and rate-limit: per account when signed in, per IP otherwise."""
        principal = None
        auth = request.headers.get("authorization", "")
        if auth.lower().startswith("bearer ") and verifier is not None:
            try:
                principal = await verifier.verify(auth[7:].strip())
            except TokenInvalid:
                metrics.inc("auth_rejected_total")
                raise HTTPException(401, "Invalid or expired token.", headers={"WWW-Authenticate": "Bearer"}) from None
        elif settings.auth_mode == "required":
            raise HTTPException(401, "Sign in required.", headers={"WWW-Authenticate": "Bearer"})
        if principal:
            key, limit = f"user:{principal.user_id}", settings.rate_limit_per_minute_user
        else:
            key, limit = f"ip:{client_key(request.scope, settings.trust_forwarded_for)}", settings.rate_limit_per_minute
        if limit > 0:
            ok, retry = await limiter.hit(key, limit)
            if not ok:
                metrics.inc("rate_limited_total")
                raise HTTPException(429, "Too many requests", headers={"Retry-After": str(retry)})
        return principal

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        async def probe(url: str) -> bool:
            try:
                return (await clients.http.get(f"{url.rstrip('/')}/ready", timeout=3.0)).status_code == 200
            except Exception:  # noqa: BLE001
                return False

        checks = {
            "eligibility-service": await probe(settings.eligibility_url),
            "retrieval-service": await probe(settings.retrieval_url),
            "llm-gateway": await probe(settings.llm_gateway_url),
        }
        # LLM down is survivable (rules-only fallback); eligibility is not.
        ok = checks["eligibility-service"]
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": checks}, status_code=200 if ok else 503)

    @app.post("/v1/recommendations", response_model=RecommendationResponse)
    async def recommendations(req: RecommendationRequest, request: Request, _p: Principal | None = Depends(edge_guard)):
        # `Cache-Control: no-cache` bypasses the response cache (used by the eval harness).
        use_cache = "no-cache" not in request.headers.get("cache-control", "").lower()
        try:
            return await pipeline.run(req, use_cache=use_cache)
        except DependencyError as e:
            raise HTTPException(503, f"{e.service} unavailable: {e.message}") from e

    @app.post("/v1/admin/cache/clear", include_in_schema=False)
    async def clear_cache(request: Request):
        """Call after re-ingesting documents or reloading eligibility rules so users don't get stale results."""
        if not settings.admin_token:
            raise HTTPException(404, "Not Found")
        if not hmac.compare_digest(request.headers.get("authorization", "").encode(), f"Bearer {settings.admin_token}".encode()):
            raise HTTPException(401, "admin token required")
        return {"cleared": await pipeline.cache.clear()}

    @app.post("/v1/explain", response_model=ExplainResponse)
    async def explain(req: ExplainRequest, _p: Principal | None = Depends(edge_guard)):
        try:
            return await pipeline.explain(req)
        except LookupError as e:
            raise HTTPException(404, str(e)) from e
        except DependencyError as e:
            raise HTTPException(503, f"{e.service} unavailable: {e.message}") from e

    @app.post("/v1/recommendations/stream")
    async def recommendations_stream(req: RecommendationRequest, _p: Principal | None = Depends(edge_guard)):
        """SSE progress: eligibility -> retrieval -> llm_token* -> result (or error)."""
        queue: asyncio.Queue = asyncio.Queue()

        async def emit(event: str, data: dict):
            await queue.put((event, data))

        async def worker():
            try:
                result = await pipeline.run(req, emit=emit, stream_llm=True)
                await queue.put(("result", result.model_dump(mode="json")))
            except DependencyError as e:
                await queue.put(("error", {"detail": f"{e.service} unavailable: {e.message}"}))
            except Exception:
                log.exception("stream pipeline failed")
                await queue.put(("error", {"detail": "internal error"}))
            await queue.put(None)

        async def events():
            task = asyncio.create_task(worker())
            try:
                while (item := await queue.get()) is not None:
                    event, data = item
                    yield {"event": event, "data": json.dumps(data, ensure_ascii=False)}
            finally:
                task.cancel()

        return EventSourceResponse(events())

    return app


def app_factory() -> FastAPI:  # uvicorn --factory recommendation_service.main:app_factory
    return create_app()
