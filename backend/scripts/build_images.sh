#!/usr/bin/env sh
# Build every service image and the scheme-docs data image.
#   scripts/build_images.sh [TAG] [REGISTRY_PREFIX]      e.g. scripts/build_images.sh 1.4.0 ghcr.io/adhikar
set -eu
TAG="${1:-local}"
PREFIX="${2:-adhikar}"
cd "$(dirname "$0")/.."
port_of() {
  case "$1" in
    recommendation-service) echo 8000 ;; llm-gateway) echo 8001 ;; embedding-service) echo 8002 ;;
    ingestion-service) echo 8003 ;; retrieval-service) echo 8004 ;; eligibility-service) echo 8005 ;;
    auth-service) echo 8006 ;; *) echo "unknown service $1" >&2; exit 1 ;;
  esac
}
for dir in services/*/; do
  svc="$(basename "$dir")"
  pkg="$(echo "$svc" | tr - _)"
  port="$(port_of "$svc")"
  echo "building $PREFIX/$svc:$TAG"
  docker build -q -f docker/service.Dockerfile \
    --build-arg SERVICE="$svc" --build-arg APP_MODULE="$pkg.main:app_factory" --build-arg PORT="$port" --build-arg VERSION="$TAG" \
    -t "$PREFIX/$svc:$TAG" .
done
echo "building $PREFIX/scheme-docs:$TAG"
docker build -q -f docker/scheme-docs.Dockerfile -t "$PREFIX/scheme-docs:$TAG" .
