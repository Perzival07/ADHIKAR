"""Copy contract_models.py into each service package (identical copies). `--check` verifies."""
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "contract_models.py"
TARGETS = {
    "llm-gateway": "llm_gateway", "embedding-service": "embedding_service",
    "ingestion-service": "ingestion_service", "retrieval-service": "retrieval_service",
    "eligibility-service": "eligibility_service", "recommendation-service": "recommendation_service",
}
bad = []
for svc, pkg in TARGETS.items():
    dst = HERE.parent / "services" / svc / "src" / pkg / "contract_models.py"
    if "--check" in sys.argv:
        if not dst.exists() or dst.read_bytes() != SRC.read_bytes():
            bad.append(svc)
    else:
        shutil.copyfile(SRC, dst)
if bad:
    print("out of sync:", bad)
    sys.exit(1)
print("ok")
