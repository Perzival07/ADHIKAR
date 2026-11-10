import logging
from contextlib import asynccontextmanager

import httpx
from adhikar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    setup_json_logging,
)
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from qdrant_client import AsyncQdrantClient

from .config import Settings, get_settings
from .contract_models import SearchRequest, SearchResponse
from .reranker import GatewayReranker, NoopReranker
from .search import Searcher, SearchUnavailable

SERVICE = "retrieval-service"
log = logging.getLogger("retrieval_service")


def create_app(settings: Settings | None = None, qdrant: AsyncQdrantClient | None = None, transport=None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    if qdrant is None:
        qdrant = AsyncQdrantClient(":memory:") if settings.qdrant_url == ":memory:" else AsyncQdrantClient(
            url=settings.qdrant_url, api_key=settings.qdrant_api_key or None
        )
    http = httpx.AsyncClient(timeout=settings.request_timeout, transport=transport)
    reranker = GatewayReranker(settings.llm_gateway_url, settings.reranker_alias, http) if settings.reranker == "llm" else NoopReranker()
    metrics = Registry()
    m_search = metrics.counter("retrieval_searches_total", "Searches", ("outcome",))
    m_chunks = metrics.counter("retrieval_chunks_returned_total", "Chunks returned", ())
    searcher = Searcher(settings, qdrant, http, reranker)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        await http.aclose()
        await qdrant.close()

    app = FastAPI(title=SERVICE, version="0.1.0", separate_input_output_schemas=False, lifespan=lifespan)
    install_metrics(app, SERVICE, metrics)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.metrics = metrics
    app.state.searcher = searcher

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        checks = {"qdrant": await searcher.collections_ok(), "embedding-service": await searcher.embedding_ready()}
        ok = all(checks.values())
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": checks}, status_code=200 if ok else 503)

    @app.post("/v1/search", response_model=SearchResponse)
    async def search(req: SearchRequest):
        try:
            chunks = await searcher.search(req)
        except SearchUnavailable as e:
            m_search.inc(outcome="unavailable")
            raise HTTPException(503, str(e)) from e
        m_search.inc(outcome="ok" if chunks else "empty")
        m_chunks.inc(len(chunks))
        log.info("search", extra={"fields": {"results": len(chunks), "schemes": len({c.scheme_id for c in chunks}), "top_k": req.top_k}})
        return SearchResponse(chunks=chunks)

    return app


def app_factory():  # uvicorn --factory <pkg>.main:app_factory (no app is built at import time)
    return create_app()
