SERVICES := auth-service llm-gateway embedding-service ingestion-service retrieval-service eligibility-service recommendation-service
VENV := .venv
# Windows venvs (PowerShell / Git Bash / cmd) use Scripts/, everything else bin/
ifeq ($(OS),Windows_NT)
BIN := $(VENV)/Scripts
else
BIN := $(VENV)/bin
endif
PY := $(BIN)/python
PIP := uv pip install --python $(PY)
K8S := ../deploy/k8s
LOCAL_PACKAGES := adhikar-common|auth-service|llm-gateway|embedding-service|ingestion-service|retrieval-service|eligibility-service|recommendation-service

help:  ## list targets
	@grep -E '^[a-zA-Z0-9_%-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort

# ---------------------------------------------------------------- development
install:  ## create .venv with every service in editable mode (needs uv)
	uv venv $(VENV) --python 3.11 -q
	$(PIP) -q -c constraints.txt -e libs/adhikar_common
	@for s in $(SERVICES); do $(PIP) -q -c constraints.txt -e "services/$$s[dev]" || exit 1; done
	$(PIP) -q -c constraints.txt httpx pytest pytest-asyncio ruff pip-audit fakeredis aiosqlite openapi-spec-validator

test:  ## unit + contract + eval + static policy tests
	@for s in $(SERVICES); do echo "== $$s"; (cd services/$$s && ../../$(PY) -m pytest -q) || exit 1; done
	@echo "== common"; (cd libs/adhikar_common && ../../$(PY) -m pytest -q)
	@echo "== contracts"; $(PY) -m pytest -q contracts/tests
	@echo "== eval"; $(PY) -m pytest -q eval/tests
	@echo "== static policies"; $(PY) -m pytest -q tests_static

test-%:  ## tests of one service, e.g. make test-auth-service
	cd services/$* && ../../$(PY) -m pytest -q

lint:  ## ruff over all python code
	$(BIN)/ruff check services libs contracts eval tests_static tests_e2e scripts

lock:  ## re-pin third-party dependencies into constraints.txt from the current venv
	{ echo "# Pinned third-party versions used by every service image (docker build uses: pip wheel -c constraints.txt)."; \
	  echo "# Regenerate with: make lock"; \
	  $(BIN)/pip freeze | grep -v -E "^-e |@ " | grep -v -i -E "^($(LOCAL_PACKAGES))==" | sort -f; } > constraints.txt

audit:  ## known-vulnerability scan of the pinned dependencies
	$(BIN)/pip-audit -r constraints.txt --no-deps --disable-pip

# ---------------------------------------------------------------- local stack (docker compose)
up:  ## build + start the local stack
	docker compose up --build -d --wait

down:  ## stop the local stack
	docker compose down

e2e:  ## start the stack and run the end-to-end suite
	docker compose up -d --build --wait
	$(PY) -m pytest -q tests_e2e

ingest:  ## (re)ingest scheme documents into the local stack
	docker compose exec -T ingestion-service python -m ingestion_service ingest

eval:  ## run the golden-set evaluation against the local stack (EVAL_TARGET, EVAL_TAG)
	$(PY) -m eval run --target $(or $(EVAL_TARGET),http://localhost:8000) --tag $(or $(EVAL_TAG),local-$$(date +%Y%m%d-%H%M))

# ---------------------------------------------------------------- real local LLM (plan P13, see SETUP_LOCAL_LLM.md)
infra:  ## only Qdrant/Redis/Postgres in Docker, published on 127.0.0.1 (for the native stack: scripts/dev_native.ps1)
	docker compose -f docker-compose.yml -f docker-compose.native.yml up -d --wait qdrant redis postgres

up-llm:  ## containerised stack on a real Ollama model server (Ollama must be reachable from Docker)
	docker compose -f docker-compose.yml -f docker-compose.llm.yml up --build -d --wait

soak:  ## sequential soak test with GPU logging (SOAK_TAG, SOAK_MINUTES=30, SOAK_TARGET)
	$(PY) scripts/soak_test.py --target $(or $(SOAK_TARGET),http://localhost:8000) --minutes $(or $(SOAK_MINUTES),30) --tag $(or $(SOAK_TAG),local)

# ---------------------------------------------------------------- images + Kubernetes
images:  ## build all images with tag `local`
	scripts/build_images.sh local adhikar

k8s-dev-secrets:  ## random secrets for the dev overlay (git-ignored)
	$(PY) scripts/gen_dev_secrets.py

k8s-render-%:  ## render an overlay, e.g. make k8s-render-prod
	kubectl kustomize $(K8S)/overlays/$*

k8s-dev-apply: k8s-dev-secrets  ## deploy the dev overlay to the current kube context
	kubectl apply -k $(K8S)/overlays/dev

.PHONY: help install test lint lock audit up down e2e ingest eval infra up-llm soak images k8s-dev-secrets k8s-dev-apply
