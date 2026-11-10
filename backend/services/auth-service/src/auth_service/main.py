from __future__ import annotations

import logging
import secrets
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import jwt
from adhikar_common import (
    AccessLogMiddleware,
    Registry,
    RequestIDMiddleware,
    install_metrics,
    make_rate_limiter,
    make_redis,
    setup_json_logging,
)
from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from .config import Settings, get_settings
from .db import User, make_engine, make_sessionmaker
from .email import EmailSender, make_sender
from .schemas import (
    ErrorOut,
    OtpLogin,
    OtpRequest,
    OtpRequested,
    PasswordLogin,
    RefreshRequest,
    SignupRequest,
    TokenPair,
    UserOut,
    UserUpdate,
)
from .security import SigningKey
from .service import AuthError, AuthService

SERVICE = "auth-service"
log = logging.getLogger("auth_service")
ERR = {400: {"model": ErrorOut}, 401: {"model": ErrorOut}, 422: {"model": ErrorOut}, 429: {"model": ErrorOut}}


def client_ip(request: Request, trust_forwarded: bool) -> str:
    if trust_forwarded:
        fwd = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
        if fwd:
            return fwd[:64]
    return request.client.host if request.client else "unknown"


def create_app(settings: Settings | None = None, sender: EmailSender | None = None, redis=None) -> FastAPI:
    settings = settings or get_settings()
    setup_json_logging(SERVICE, settings.log_level)
    engine = make_engine(settings.database_url)
    sessions = make_sessionmaker(engine)
    key = SigningKey.load(settings.jwt_private_key)
    if not settings.jwt_private_key:
        log.warning("AUTH_JWT_PRIVATE_KEY not set: using an ephemeral development key (tokens die on restart)")
    otp_secret = settings.otp_secret or secrets.token_hex(32)
    svc = AuthService(settings, key, sender or make_sender(settings), otp_secret)
    redis = redis if redis is not None else make_redis(settings.redis_url)
    limiter = make_rate_limiter(redis, "auth:rl")
    metrics = Registry()
    m_events = metrics.counter("auth_events_total", "Auth events", ("event", "outcome"))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if settings.seed_demo_users:
            from .seed import seed_demo_users

            async with sessions() as db:
                await seed_demo_users(db)
        yield
        await engine.dispose()

    app = FastAPI(title=SERVICE, version="1.0.0", separate_input_output_schemas=False, lifespan=lifespan)
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    if origins:
        app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST", "PATCH", "DELETE"],
                           allow_headers=["authorization", "content-type", "x-request-id"], expose_headers=["X-Request-ID"])
    install_metrics(app, SERVICE, metrics)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIDMiddleware)
    app.state.engine, app.state.sessions, app.state.service, app.state.key = engine, sessions, svc, key

    @app.exception_handler(AuthError)
    async def auth_error(_: Request, e: AuthError):
        headers = {"Retry-After": str(e.retry_after)} if e.retry_after else None
        if e.status == 401:
            headers = {**(headers or {}), "WWW-Authenticate": "Bearer"}
        return JSONResponse({"detail": e.detail}, status_code=e.status, headers=headers)

    async def db() -> AsyncIterator[AsyncSession]:
        async with sessions() as s:
            yield s

    async def ip_limit(request: Request) -> None:
        ok, retry = await limiter.hit(f"ip:{client_ip(request, settings.trust_forwarded_for)}", settings.rate_limit_per_minute)
        if not ok:
            raise AuthError(429, "Too many requests.", retry_after=retry)

    async def current_user(request: Request, s: AsyncSession = Depends(db)) -> User:
        auth = request.headers.get("authorization", "")
        if not auth.lower().startswith("bearer "):
            raise AuthError(401, "Missing bearer token.")
        try:
            claims = key.verify(auth[7:].strip(), settings.jwt_issuer, settings.jwt_audience)
            user = await s.get(User, uuid.UUID(claims["sub"]))
        except (jwt.PyJWTError, ValueError):
            raise AuthError(401, "Invalid or expired token.") from None
        if user is None or not user.is_active:
            raise AuthError(401, "Invalid or expired token.")
        return user

    def pair(user: User, access: str, refresh: str) -> TokenPair:
        return TokenPair(access_token=access, expires_in=settings.access_token_ttl, refresh_token=refresh,
                         refresh_expires_in=settings.refresh_token_ttl, user=svc.user_out(user))

    # ------------------------------------------------------------------ probes
    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok", "service": SERVICE}

    @app.get("/ready")
    async def ready():
        try:
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            ok = True
        except Exception:  # noqa: BLE001
            ok = False
        return JSONResponse({"ready": ok, "service": SERVICE, "checks": {"database": ok}}, status_code=200 if ok else 503)

    @app.get("/.well-known/jwks.json")
    async def jwks(response: Response) -> dict:
        response.headers["Cache-Control"] = "public, max-age=300"
        return key.jwks()

    # ------------------------------------------------------------------ auth flows
    @app.post("/v1/auth/otp/request", response_model=OtpRequested, status_code=202, responses=ERR, dependencies=[Depends(ip_limit)])
    async def otp_request(req: OtpRequest, s: AsyncSession = Depends(db)):
        try:
            wait = await svc.request_otp(s, req.email, req.purpose)
        except AuthError as e:
            m_events.inc(event="otp_request", outcome=str(e.status))
            raise
        m_events.inc(event="otp_request", outcome="ok")
        return OtpRequested(resend_after=wait)

    @app.post("/v1/auth/signup", response_model=TokenPair, status_code=201, responses=ERR, dependencies=[Depends(ip_limit)])
    async def signup(req: SignupRequest, s: AsyncSession = Depends(db)):
        try:
            user, access, refresh = await svc.signup(s, req)
        except AuthError as e:
            m_events.inc(event="signup", outcome=str(e.status))
            raise
        m_events.inc(event="signup", outcome="ok")
        return pair(user, access, refresh)

    @app.post("/v1/auth/login", response_model=TokenPair, responses=ERR, dependencies=[Depends(ip_limit)])
    async def login(req: PasswordLogin, s: AsyncSession = Depends(db)):
        try:
            user, access, refresh = await svc.login_password(s, req.identifier, req.password)
        except AuthError as e:
            m_events.inc(event="login_password", outcome=str(e.status))
            raise
        m_events.inc(event="login_password", outcome="ok")
        return pair(user, access, refresh)

    @app.post("/v1/auth/login/otp", response_model=TokenPair, responses=ERR, dependencies=[Depends(ip_limit)])
    async def login_otp(req: OtpLogin, s: AsyncSession = Depends(db)):
        try:
            user, access, refresh = await svc.login_otp(s, req.email, req.code)
        except AuthError as e:
            m_events.inc(event="login_otp", outcome=str(e.status))
            raise
        m_events.inc(event="login_otp", outcome="ok")
        return pair(user, access, refresh)

    @app.post("/v1/auth/token/refresh", response_model=TokenPair, responses=ERR, dependencies=[Depends(ip_limit)])
    async def refresh(req: RefreshRequest, s: AsyncSession = Depends(db)):
        user, access, new_refresh = await svc.refresh(s, req.refresh_token)
        return pair(user, access, new_refresh)

    @app.post("/v1/auth/logout", status_code=204, dependencies=[Depends(ip_limit)])
    async def logout(req: RefreshRequest, s: AsyncSession = Depends(db)):
        await svc.logout(s, req.refresh_token)
        return Response(status_code=204)

    @app.post("/v1/auth/logout-all", status_code=204, responses=ERR)
    async def logout_all(user: User = Depends(current_user), s: AsyncSession = Depends(db)):
        await svc.logout_all(s, user.id)
        return Response(status_code=204)

    # ------------------------------------------------------------------ profile
    @app.get("/v1/users/me", response_model=UserOut, responses=ERR)
    async def me(user: User = Depends(current_user)):
        return svc.user_out(user)

    @app.patch("/v1/users/me", response_model=UserOut, responses=ERR)
    async def update_me(upd: UserUpdate, user: User = Depends(current_user), s: AsyncSession = Depends(db)):
        merged = await s.merge(user)
        return svc.user_out(await svc.update_user(s, merged, upd))

    @app.delete("/v1/users/me", status_code=204, responses=ERR)
    async def delete_me(user: User = Depends(current_user), s: AsyncSession = Depends(db)):
        await svc.delete_user(s, await s.merge(user))
        m_events.inc(event="account_deleted", outcome="ok")
        return Response(status_code=204)

    return app


def app_factory() -> FastAPI:  # uvicorn --factory auth_service.main:app_factory
    return create_app()
