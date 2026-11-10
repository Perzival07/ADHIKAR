"""Static policy checks over the whole backend (run as part of `make test`)."""
from __future__ import annotations

import ast
import re
from pathlib import Path

import pytest
import yaml

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
SRC_DIRS = [*sorted((BACKEND / "services").glob("*/src")), BACKEND / "libs" / "haqdaar_common" / "src"]
PY_FILES = [p for d in SRC_DIRS for p in d.rglob("*.py") if p.name != "contract_models.py"]

# profile fields that must never reach a log line
SENSITIVE = {
    "socialCategory", "annualIncomeRange", "rationCard", "disabilityStatus", "maritalStatus", "occupation",
    "landHoldingAcres", "artisanTrade", "studentLevel", "hasGirlChildUnder10", "gender", "district", "age",
}
LOG_METHODS = {"debug", "info", "warning", "warn", "error", "exception", "critical", "log"}
SAFE_WRAPPERS = {"redact_profile", "profile_hash"}


def _parents(tree: ast.AST) -> dict[ast.AST, ast.AST]:
    return {child: parent for parent in ast.walk(tree) for child in ast.iter_child_nodes(parent)}


def _is_log_call(node: ast.Call) -> bool:
    f = node.func
    return isinstance(f, ast.Attribute) and f.attr in LOG_METHODS and isinstance(f.value, ast.Name) and f.value.id in {"log", "logger", "logging"}


def _inside_safe_wrapper(node: ast.AST, parents: dict[ast.AST, ast.AST], stop: ast.AST) -> bool:
    cur = parents.get(node)
    while cur is not None and cur is not stop:
        if isinstance(cur, ast.Call):
            name = cur.func.id if isinstance(cur.func, ast.Name) else getattr(cur.func, "attr", "")
            if name in SAFE_WRAPPERS:
                return True
        cur = parents.get(cur)
    return False


def _violations(source: str, filename: str = "<src>") -> list[str]:
    tree = ast.parse(source)
    parents = _parents(tree)
    out = []
    for call in (n for n in ast.walk(tree) if isinstance(n, ast.Call) and _is_log_call(n)):
        for node in ast.walk(call):
            if node is call.func or node is call:
                continue
            name = None
            if isinstance(node, ast.Name) and node.id in {"profile", "req", "request"}:
                # the bare object (or `profile` itself) must not be logged; `req.top_k` etc. is fine and is
                # still checked through the SENSITIVE / .profile attribute rules below
                parent = parents.get(node)
                bare = not (isinstance(parent, ast.Attribute) and parent.value is node)
                name = node.id if (bare or node.id == "profile") else None
            elif isinstance(node, ast.Attribute) and (node.attr in SENSITIVE or node.attr == "profile"):
                name = node.attr
            elif isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value in SENSITIVE:
                name = node.value
            if name and not _inside_safe_wrapper(node, parents, call):
                out.append(f"{filename}:{node.lineno}: log call uses {name!r}")
    return out


@pytest.mark.parametrize("path", PY_FILES, ids=lambda p: str(p.relative_to(BACKEND)))
def test_no_profile_fields_in_log_calls(path):
    assert _violations(path.read_text(), str(path.relative_to(BACKEND))) == []


def test_checker_catches_leaks_and_allows_redaction():
    leak = 'import logging\nlog = logging.getLogger("x")\ndef f(profile, req):\n    log.info("p %s", profile.socialCategory)\n    log.info("r", extra={"fields": {"rc": req.profile.rationCard}})\n    log.warning(f"x {profile}")\n'
    assert len(_violations(leak)) >= 3
    assert _violations('log = None\ndef f(req):\n    log.info("x", extra={"fields": {"k": req.top_k}})\n') == []
    assert len(_violations('log = None\ndef f(req):\n    log.info("x %s", req)\n')) == 1
    ok = 'log = None\ndef f(profile):\n    log.info("req", extra={"fields": {**redact_profile(profile.model_dump()), "h": profile_hash({})}})\n'
    assert _violations(ok) == []


def test_all_services_were_scanned():
    names = {p.parts[-4] if "services" in p.parts else "common" for p in PY_FILES}
    assert {"auth-service", "llm-gateway", "embedding-service", "ingestion-service", "retrieval-service", "eligibility-service",
            "recommendation-service"} <= names


# ------------------------------------------------------------------ network exposure
ONE_SHOT = {"auth-migrate"}


def test_only_the_public_apis_publish_ports():
    compose = yaml.safe_load((BACKEND / "docker-compose.yml").read_text())
    published = {name for name, svc in compose["services"].items() if svc.get("ports")}
    assert published == {"recommendation-service", "auth-service"}
    for name, svc in compose["services"].items():
        if name not in ONE_SHOT:
            assert "healthcheck" in svc, f"{name} has no healthcheck"
    assert compose["networks"]["internal"] is not None


def test_internal_services_do_not_use_host_network():
    compose = yaml.safe_load((BACKEND / "docker-compose.yml").read_text())
    for name, svc in compose["services"].items():
        assert svc.get("network_mode") != "host", name


def test_service_image_is_non_root_multistage_and_pinned():
    text = (BACKEND / "docker" / "service.Dockerfile").read_text()
    assert re.search(r"^USER 10001:10001$", text, re.MULTILINE) and "useradd" in text
    assert "-c constraints.txt" in text, "wheels must be built with the pinned constraints"
    assert text.count("FROM ") == 2 and "--no-index" in text, "runtime installs only the prebuilt wheels"
    assert "--timeout-graceful-shutdown" in text and "STOPSIGNAL SIGTERM" in text
    assert not list((BACKEND / "services").glob("*/Dockerfile")), "use docker/service.Dockerfile for every service"


def test_every_service_starts_from_an_app_factory():
    for main in (BACKEND / "services").glob("*/src/*/main.py"):
        src = main.read_text()
        assert "def app_factory" in src, main
        assert not re.search(r"^app = create_app\(\)", src, re.MULTILINE), f"{main}: no app at import time"


def test_compose_builds_every_service_from_the_shared_dockerfile():
    compose = yaml.safe_load((BACKEND / "docker-compose.yml").read_text())
    services = {p.name for p in (BACKEND / "services").iterdir() if p.is_dir()}
    built = {svc["build"]["args"]["SERVICE"] for svc in compose["services"].values() if "build" in svc}
    assert built == services


# ------------------------------------------------------------------ secrets
SECRET_ASSIGN = re.compile(r"""(?ix)\b(password|passwd|secret|api[_-]?key|app[_-]?password|token)\w*\s*[:=]\s*["'][A-Za-z0-9_\-/+=]{12,}["']""")
SCAN_ROOTS = [BACKEND / "services", BACKEND / "libs", BACKEND / "docker-compose.yml", REPO / "lib", REPO / "web", REPO / "pubspec.yaml"]


def _scan_files():
    for root in SCAN_ROOTS:
        files = [root] if root.is_file() else [p for p in root.rglob("*") if p.is_file()]
        for p in files:
            if p.suffix in {".py", ".dart", ".yaml", ".yml", ".json", ".md", ".html", ".js", ".txt", ".env", ""} and \
                    "tests" not in p.parts and "node_modules" not in p.parts and ".venv" not in p.parts and "corpus" not in p.name \
                    and "schemes_corpus" not in p.name and "internships_corpus" not in p.name and p.stat().st_size < 2_000_000:
                yield p


def test_no_hardcoded_secrets_in_source():
    hits = []
    for p in _scan_files():
        for i, line in enumerate(p.read_text(errors="ignore").splitlines(), 1):
            if SECRET_ASSIGN.search(line):
                hits.append(f"{p.relative_to(REPO)}:{i}: {line.strip()[:100]}")
    assert hits == [], hits


def test_tokens_are_compared_in_constant_time():
    plain = re.compile(r"""(==|!=)\s*f?["']Bearer """)
    hits = [f"{p.relative_to(BACKEND)}:{i}" for p in PY_FILES
            for i, line in enumerate(p.read_text().splitlines(), 1) if plain.search(line)]
    assert hits == [], f"use hmac.compare_digest for secret tokens: {hits}"


def test_env_files_are_git_ignored_and_examples_have_no_values():
    gi = (BACKEND / ".gitignore").read_text()
    assert re.search(r"^\.env$", gi, re.MULTILINE)
    root_gi = (REPO / ".gitignore").read_text()
    assert re.search(r"^\.env$", root_gi, re.MULTILINE)
    for ex in (BACKEND / "services").glob("*/.env.example"):
        for line in ex.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                key, _, val = line.partition("=")
                assert not re.search(r"(?i)(password|secret|key|token)", key) or val == "", f"{ex}: {key} must be empty"


def test_flutter_assets_do_not_bundle_env_files():
    pubspec = (REPO / "pubspec.yaml").read_text()
    assert not re.search(r"^\s*-\s*\.env\s*$", pubspec, re.MULTILINE)


# ------------------------------------------------------------------ dependency pinning
def test_constraints_file_pins_exact_versions():
    lines = [ln.strip() for ln in (BACKEND / "constraints.txt").read_text().splitlines() if ln.strip() and not ln.startswith("#")]
    assert len(lines) > 30
    for ln in lines:
        assert re.match(r"^[A-Za-z0-9_.\-\[\]]+==[0-9][A-Za-z0-9.\-+!]*$", ln), f"not pinned: {ln}"
    names = {ln.split("==")[0].lower() for ln in lines}
    assert {"fastapi", "pydantic", "httpx", "qdrant-client", "uvicorn"} <= names


# ------------------------------------------------------------------ deployment consistency
def test_k8s_llm_models_match_the_service_default():
    assert (REPO / "deploy" / "k8s" / "base" / "models.yaml").read_text() == \
        (BACKEND / "services" / "llm-gateway" / "models.yaml").read_text(), "copy services/llm-gateway/models.yaml to deploy/k8s/base/"


def test_k8s_deployments_are_hardened():
    for f in (REPO / "deploy" / "k8s" / "base").glob("*-service.yaml"):
        docs = [d for d in yaml.safe_load_all(f.read_text()) if d]
        dep = next(d for d in docs if d["kind"] == "Deployment")
        pod = dep["spec"]["template"]["spec"]
        assert pod["securityContext"]["runAsNonRoot"] is True and pod["automountServiceAccountToken"] is False, f.name
        c = pod["containers"][0]
        assert c["securityContext"]["readOnlyRootFilesystem"] is True and c["securityContext"]["capabilities"]["drop"] == ["ALL"], f.name
        assert {"startupProbe", "livenessProbe", "readinessProbe"} <= set(c), f.name
        assert c["resources"]["requests"] and c["resources"]["limits"], f.name
        assert any(e["name"] == "PORT" for e in c["env"]), f"{f.name}: PORT must be explicit"
        kinds = {d["kind"] for d in docs}
        assert "PodDisruptionBudget" in kinds, f.name


def test_markdown_links_resolve():
    import re as _re

    md_files = [*REPO.glob("*.md"), *(REPO / "docs").rglob("*.md"), *BACKEND.glob("*.md")]
    broken = []
    for md in md_files:
        for target in _re.findall(r"\]\(([^)#\s]+)\)", md.read_text()):
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (md.parent / target).exists():
                broken.append(f"{md.relative_to(REPO)} -> {target}")
    assert broken == [], broken
