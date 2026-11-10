import logging
import signal
import threading
from contextlib import asynccontextmanager

from adhikar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    redact_profile,
    setup_json_logging,
)
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from .config import Settings, get_settings
from .contract_models import EligibilityRequest, EligibilityResponse
from .engine import Engine, Rules
from .schemes import load_schemes

SERVICE = "eligibility-service"
log = logging.getLogger("eligibility_service")


class State:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._lock = threading.Lock()
        self.engine = self._build()

    def _build(self) -> Engine:
        schemes = load_schemes(self.settings.docs_dir)
        log.info("loaded %d schemes", len(schemes))
        return Engine(schemes, Rules.load())

    def reload(self) -> int:
        engine = self._build()  # build first; keep the old engine if this raises
        with self._lock:
            self.engine = engine
        return len(engine.schemes)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    state = State(settings)
    metrics = Registry()
    m_eval = metrics.counter("eligibility_evaluations_total", "Eligibility requests", ())
    m_res = metrics.counter("eligibility_results_total", "Per-scheme results", ("status",))
    m_schemes = metrics.gauge("eligibility_schemes_loaded", "Schemes loaded from the documents folder", ())
    m_schemes.set(len(state.engine.schemes))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        try:
            signal.signal(signal.SIGHUP, lambda *_: state.reload())
        except (ValueError, AttributeError):  # not main thread / unsupported platform
            pass
        yield

    app = FastAPI(title=SERVICE, version="0.1.0", separate_input_output_schemas=False, lifespan=lifespan)
    install_metrics(app, SERVICE, metrics)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.metrics = metrics
    app.state.eligibility = state

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        n = len(state.engine.schemes)
        ok = n > 0
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": {"schemes_loaded": n}}, status_code=200 if ok else 503)

    @app.post("/v1/eligibility", response_model=EligibilityResponse)
    async def eligibility(req: EligibilityRequest):
        log.info("eligibility request", extra={"fields": redact_profile(req.profile.model_dump())})
        results = state.engine.evaluate(req.profile, req.scheme_ids)
        m_eval.inc()
        for r in results:
            m_res.inc(status=r.status)
        return EligibilityResponse(results=results)

    @app.post("/v1/admin/reload")
    async def reload_schemes():
        n = state.reload()
        m_schemes.set(n)
        return {"schemes": n}

    return app


def app_factory():  # uvicorn --factory <pkg>.main:app_factory (no app is built at import time)
    return create_app()
