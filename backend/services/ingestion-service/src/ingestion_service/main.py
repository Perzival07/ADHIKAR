import asyncio
import logging
from contextlib import asynccontextmanager

from adhikar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    setup_json_logging,
)
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from .config import Settings, get_settings
from .contract_models import DeleteDocResponse, IngestRequest, IngestStatus
from .embedding_client import EmbeddingClient, EmbeddingError
from .ingest import Ingestor
from .manifest import Manifest
from .store import Store, make_client

SERVICE = "ingestion-service"
log = logging.getLogger("ingestion_service")


def build_ingestor(settings: Settings, qdrant=None, transport=None) -> Ingestor:
    store = Store(qdrant or make_client(settings))
    embedder = EmbeddingClient(settings.embedding_url, settings.request_timeout, settings.embed_batch, transport)
    return Ingestor(settings, store, embedder, Manifest(settings.state_dir))


def create_app(settings: Settings | None = None, qdrant=None, transport=None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    ingestor = build_ingestor(settings, qdrant, transport)
    metrics = Registry()
    ingestor.metrics = metrics
    task: dict[str, asyncio.Task | None] = {"t": None}

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        watcher = None
        if settings.watch:
            from .watcher import watch_forever

            watcher = asyncio.create_task(watch_forever(ingestor))
        yield
        if watcher:
            watcher.cancel()
        await ingestor.embedder.aclose()
        await ingestor.store.client.close()

    app = FastAPI(title=SERVICE, version="0.1.0", separate_input_output_schemas=False, lifespan=lifespan)
    install_metrics(app, SERVICE, metrics)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.metrics = metrics
    app.state.ingestor = ingestor

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        checks = {"qdrant": await ingestor.store.healthy(), "embedding-service": await ingestor.embedder.ready()}
        ok = all(checks.values())
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": checks}, status_code=200 if ok else 503)

    @app.post("/v1/ingest", response_model=IngestStatus)
    async def ingest(req: IngestRequest):
        if task["t"] and not task["t"].done():
            return ingestor.status  # already running; report progress instead of starting another
        try:
            ingestor.resolve_scope(req.path)
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
        ingestor.status = IngestStatus(state="running")
        task["t"] = asyncio.create_task(ingestor.run(req.path, req.force))
        await asyncio.sleep(0)  # let the run start
        return ingestor.status

    @app.get("/v1/ingest/status", response_model=IngestStatus)
    async def ingest_status():
        return ingestor.status

    @app.delete("/v1/docs/{scheme_id}", response_model=DeleteDocResponse)
    async def delete_doc(scheme_id: str):
        try:
            n = await ingestor.delete_scheme(scheme_id)
        except EmbeddingError as e:
            raise HTTPException(503, str(e)) from e
        return DeleteDocResponse(scheme_id=scheme_id, chunks_deleted=n)

    return app


def app_factory():  # uvicorn --factory <pkg>.main:app_factory (no app is built at import time)
    return create_app()
