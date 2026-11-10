# syntax=docker/dockerfile:1.7
# One image recipe for every backend service.
#   docker build -f docker/service.Dockerfile --build-arg SERVICE=auth-service --build-arg APP_MODULE=auth_service.main:app_factory --build-arg PORT=8006 .
ARG PYTHON_VERSION=3.11

# ---- build: wheels for the service + its pinned dependencies (no compilers in the runtime image)
FROM python:${PYTHON_VERSION}-slim AS build
ARG SERVICE
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /src
COPY constraints.txt ./
COPY libs/adhikar_common ./libs/adhikar_common
COPY services/${SERVICE} ./services/${SERVICE}
RUN pip wheel --wheel-dir /wheels -c constraints.txt ./libs/adhikar_common ./services/${SERVICE}

# ---- runtime
FROM python:${PYTHON_VERSION}-slim AS runtime
ARG SERVICE
ARG APP_MODULE
ARG PORT=8000
ARG VERSION=dev
LABEL org.opencontainers.image.title="adhikar-${SERVICE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/adhikar/adhikar"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_MODULE=${APP_MODULE} \
    PORT=${PORT} \
    WEB_CONCURRENCY=1 \
    SERVICE_VERSION=${VERSION}
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --no-create-home --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /app /state \
    && chown app:app /state
COPY --from=build /wheels /wheels
RUN pip install --no-cache-dir --no-index /wheels/*.whl && rm -rf /wheels
WORKDIR /app
USER 10001:10001
EXPOSE ${PORT}
STOPSIGNAL SIGTERM
# --proxy-headers: client IPs come from the ingress; graceful shutdown lets in-flight requests finish on rollout
CMD ["sh", "-c", "exec uvicorn --factory \"$APP_MODULE\" --host 0.0.0.0 --port \"$PORT\" --workers \"$WEB_CONCURRENCY\" --proxy-headers --forwarded-allow-ips='*' --timeout-graceful-shutdown 25 --no-access-log"]
