SERVICES := auth-service llm-gateway embedding-service ingestion-service retrieval-service eligibility-service recommendation-service
VENV := .venv
PY := $(VENV)/bin/python
PIP := uv pip install --python $(PY)
K8S := ../deploy/k8s
LOCAL_PACKAGES := haqdaar-common|auth-service|llm-gateway|embedding-service|ingestion-service|retrieval-service|eligibility-service|recommendation-service

help:  ## list targets
	@grep -E '^[a-zA-Z0-9_%-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort

# ---------------------------------------------------------------- development
install:  ## create .venv with every service in editable mode (needs uv)
	uv venv $(VENV) --python 3.11 -q
	$(PIP) -q -c constraints.txt -e libs/haqdaar_common
	@for s in $(SERVICES); do $(PIP) -q -c constraints.txt -e "services/$$s[dev]" || exit 1; done
	$(PIP) -q -c constraints.txt httpx pytest pytest-asyncio ruff pip-audit fakeredis aiosqlite openapi-spec-validator

test:  ## unit + contract + eval + static policy tests
	@for s in $(SERVICES); do echo "== $$s"; (cd services/$$s && ../../$(PY) -m pytest -q) || exit 1; done
	@echo "== common"; (cd libs/haqdaar_common && ../../$(PY) -m pytest -q)
	@echo "== contracts"; $(PY) -m pytest -q contracts/tests
	@echo "== eval"; $(PY) -m pytest -q eval/tests
	@echo "== static policies"; $(PY) -m pytest -q tests_static

test-%:  ## tests of one service, e.g. make test-auth-service
	cd services/$* && ../../$(PY) -m pytest -q

lint:  ## ruff over all python code
	$(VENV)/bin/ruff check services libs contracts eval tests_static tests_e2e scripts

lock:  ## re-pin third-party dependencies into constraints.txt from the current venv
	{ echo "# Pinned third-party versions used by every service image (docker build uses: pip wheel -c constraints.txt)."; \
	  echo "# Regenerate with: make lock"; \
	  $(VENV)/bin/pip freeze | grep -v -E "^-e |@ " | grep -v -i -E "^($(LOCAL_PACKAGES))==" | sort -f; } > constraints.txt

audit:  ## known-vulnerability scan of the pinned dependencies
	$(VENV)/bin/pip-audit -r constraints.txt --no-deps --disable-pip

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

eval:  ## run the golden-set evaluation against the local stack
	$(PY) -m eval run --target http://localhost:8000 --tag local-$$(date +%Y%m%d-%H%M)

# ---------------------------------------------------------------- images + Kubernetes
images:  ## build all images with tag `local`
	scripts/build_images.sh local haqdaar

k8s-dev-secrets:  ## random secrets for the dev overlay (git-ignored)
	$(PY) scripts/gen_dev_secrets.py

k8s-render-%:  ## render an overlay, e.g. make k8s-render-prod
	kubectl kustomize $(K8S)/overlays/$*

k8s-dev-apply: k8s-dev-secrets  ## deploy the dev overlay to the current kube context
	kubectl apply -k $(K8S)/overlays/dev

.PHONY: help install test lint lock audit up down e2e ingest eval images k8s-dev-secrets k8s-dev-apply
