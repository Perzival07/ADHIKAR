# Running a real local LLM (plan P13)

This is the step-by-step record for the development PC (RTX 3070 Ti 8 GB for inference, GTX 1650 Super 4 GB for the
display, i5-10500, 32 GB RAM, Windows 10). Everything here is configuration: no service code changed.

Status legend: **done** = performed on 2026-11-11, **you** = needs a physical / admin action by the owner.

## 0. Decision: native services, Ollama on loopback

Ollama listens on `127.0.0.1:11434` only (its default). Docker containers cannot reach the host's loopback, so the
containerised stack (`docker-compose.yml`) cannot use it without exposing Ollama on all interfaces. Instead the
Python services run **natively** from `.venv` and only the stateful infrastructure (Qdrant, Redis, Postgres) runs in
Docker, published on `127.0.0.1`. Nothing new is reachable from the network.

```
Flutter app ──► recommendation-service :8000 (native) ──► eligibility :8005, retrieval :8004, llm-gateway :8001 (native)
                                                                            │                 │
                                                              embedding :8002 (native, CPU)   Ollama :11434 (GPU 0)
                                                                            │
                                      Docker (127.0.0.1 only): qdrant :6333, redis :6379, postgres :5432
```

If you prefer containers, `docker-compose.llm.yml` is ready; it needs `OLLAMA_HOST=0.0.0.0` on the host plus a
firewall rule that allows port 11434 only from the Docker/WSL subnet. That is your call, not done here.

## 1. GPU roles and driver stability

| Step | State |
|---|---|
| Inference pinned to the 3070 Ti: `CUDA_VISIBLE_DEVICES=GPU-6c541481-c0e8-4698-293d-5a77bb2b7088` (its UUID from `nvidia-smi -L`, so the index can never be confused) | **done** (user env var) |
| Monitors on the GTX 1650 Super, none on the 3070 Ti | **you**. On 2026-11-11 `nvidia-smi` showed the display active on the 3070 Ti with ~4.5 GB VRAM already used by desktop apps (Chrome, IDE, messaging). That leaves ~3.5 GB for the model, below the 3 GB headroom rule once a 3B model (~2.5 to 3.5 GB with a 4k context) is loaded. Move the cables, or close GPU-heavy apps before soak tests. |
| Current NVIDIA Studio driver | **you** (installed driver: 617.42; check for a newer Studio release) |
| Power limit ~75 % (`nvidia-smi -i 0 -pl 220`, admin). Persist with a Task Scheduler job "at log on, run as admin": `nvidia-smi -i 0 -pl 220` | **you** (optional, recommended; the card was at 78 °C / 170 W under desktop load alone) |
| Never split one model across both GPUs | guaranteed by `CUDA_VISIBLE_DEVICES` |

## 2. Ollama settings

Installed with `winget install Ollama.Ollama` (0.40.16). User-level environment variables (restart the Ollama tray
app after changing them):

| Variable | Value | Why |
|---|---|---|
| `OLLAMA_NUM_PARALLEL` | `1` | one request at a time on the GPU |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | a single model resident; VRAM is predictable |
| `OLLAMA_KEEP_ALIVE` | `30m` | no reload churn between requests, VRAM freed when idle |
| `OLLAMA_MODELS` | `D:\ollama-models` | intended weights location. The running app still used `C:\Users\dasko\.ollama\models` (3.7 GB, fine). Quit and restart the Ollama tray app, then re-pull, to move them. |
| `CUDA_VISIBLE_DEVICES` | 3070 Ti UUID | inference GPU only |
| `OLLAMA_HOST` | *(unset = 127.0.0.1:11434)* | never on an untrusted network |

Check: `ollama ps` after a request must show the model `100% GPU`; `nvidia-smi` must show `ollama.exe` on GPU 0.

## 3. Model candidates

All ≤ 3B, Q4_K_M, pulled with `ollama pull <tag>`:

| Candidate | Tag | Size | Why |
|---|---|---|---|
| 1 (first choice) | `qwen2.5:3b-instruct-q4_K_M` | ~2.0 GB | best JSON / instruction following at this size |
| 2 | `llama3.2:3b-instruct-q4_K_M` | ~2.0 GB | Hindi officially supported; good fine-tune base for P17 |

Later options: Gemma 3 4B (`gemma3:4b`, ~3.3 GB, tighter on VRAM), Qwen3 4B (needs `think: false` in the request,
not sent by the gateway yet), Sarvam-1 (base model, only after fine-tuning).
VRAM budget: 3B @ Q4 + 4k context ≈ 2.5 to 3.5 GB. Never raise `num_ctx` above 8192.

## 4. Embeddings on the CPU

`BAAI/bge-m3` (multilingual, 1024-d) downloaded to `D:\models\bge-m3` with `huggingface_hub.snapshot_download`
(safetensors + tokenizer only, ~2.3 GB), and `sentence-transformers` installed into `.venv` (CPU-only torch wheel
from PyPI on Windows). The service runs it with `EMBED_DEVICE=cpu`, `HF_HUB_OFFLINE=1`, so the GPU stays free.

Lighter alternative if ingestion is too slow on the i5: `intfloat/multilingual-e5-base` with
`EMBED_QUERY_PREFIX="query: "` and `EMBED_DOCUMENT_PREFIX="passage: "`.

The Qdrant collection name contains the embedding model id, so switching embedders = re-run ingestion.

## 5. Wiring (config only)

| What | Where | Value |
|---|---|---|
| `recommender` and `translate` aliases → Ollama | `services/llm-gateway/models.ollama.yaml` | `provider: ollama`, `model: qwen2.5:3b-instruct-q4_K_M`, `options: {num_ctx: 4096, keep_alive: 30m}` |
| Gateway | env (set by the script) | `LLMGW_MODELS_FILE=<that file>`, `LLMGW_OLLAMA_BASE_URL=http://127.0.0.1:11434`, `LLMGW_CONCURRENCY=1`, `LLMGW_READ_TIMEOUT=180` |
| Embeddings | env | `EMBED_PROVIDER=sentence_transformers`, `EMBED_MODEL_PATH=D:\models\bge-m3`, `EMBED_DEVICE=cpu` |
| Recommendation budget | default | `RECO_CONTEXT_TOKEN_BUDGET=3000`; timeouts raised to `RECO_LLM_TIMEOUT=150`, `RECO_REQUEST_DEADLINE=180` for a cold model |
| `models.yaml` (mock) | unchanged | CI, `make up` and the Kubernetes dev overlay keep working without a model server |

Run it:

```powershell
cd backend
scripts/dev_native.ps1 up          # infra + 7 services; waits for /ready
scripts/dev_native.ps1 ingest      # first time, and after every embedder change (~10-40 min on the CPU)
scripts/dev_native.ps1 status
curl.exe -s http://127.0.0.1:8001/v1/models      # aliases -> provider ollama
curl.exe -s http://127.0.0.1:8001/ready          # per-alias health
```

Switch candidate: edit `model:` in `models.ollama.yaml`, then `scripts/dev_native.ps1 up` again (it restarts the
services). Switch back to mock: `scripts/dev_native.ps1 up -Mock`.

## 6. Soak test

```powershell
make soak SOAK_TAG=qwen25-3b SOAK_MINUTES=30     # or: .venv\Scripts\python scripts\soak_test.py --tag qwen25-3b
```

`scripts/soak_test.py` sends sequential requests with `Cache-Control: no-cache` (every one hits the model), cycling
through the 46 golden profiles in English and Hindi, and samples `nvidia-smi` every 10 s.
Output: `eval/results/soak-<tag>.json` (p50/p95/max latency, errors, fallbacks, peak VRAM/temperature/power, pass/fail)
and `eval/results/soak-<tag>.gpu.csv`.

PASS = no HTTP errors, no rules-only fallbacks, no `nvidia-smi` failures (a driver reset makes it fail), peak VRAM
≤ 5.5 GB, and the desktop stayed responsive (your judgement). Keep the monitors on the 1650 Super during the test.

## 7. Evaluate each candidate

```powershell
make eval EVAL_TARGET=http://127.0.0.1:8000 EVAL_TAG=qwen25-3b
# edit models.ollama.yaml -> llama3.2:3b-instruct-q4_K_M, restart, then:
make eval EVAL_TARGET=http://127.0.0.1:8000 EVAL_TAG=llama32-3b
.venv\Scripts\python -m eval compare eval\results\qwen25-3b.json eval\results\llama32-3b.json
```

Pick the winner on: must_include recall@10, hallucinated-id rate (`model_hallucination_rate`), JSON-valid rate,
citation coverage, latency p95, and a manual spot-check of 20 Hindi reasons. Record the decision here and set the
winner in `models.ollama.yaml`. Commit the two result files (`eval/results/baseline*.json` are kept by git; rename
the winner's file to `baseline-<model>.json`).

## 8. Troubleshooting

| Symptom | Check |
|---|---|
| "Display driver stopped responding" | monitors must be on the 1650 Super; lower the power limit; lower `num_ctx` to 3072 |
| Model runs on the CPU (`ollama ps` shows `CPU` or a split) | `CUDA_VISIBLE_DEVICES` is set for the Ollama *app* process (restart it); VRAM already used by the desktop |
| llm-gateway `/ready` false for `recommender` | Ollama not running, or `LLMGW_OLLAMA_BASE_URL` wrong; `curl 127.0.0.1:11434/api/tags` |
| `invalid_json` fallbacks | prompt v2 and temperature ≤ 0.3 are already the defaults; this is the motivation for P16/P17 |
| `llm_504` / timeouts on the first request | cold load; `OLLAMA_KEEP_ALIVE=30m` prevents repeats; raise `LLMGW_READ_TIMEOUT` |
| retrieval `/ready` says the index does not exist | run `scripts/dev_native.ps1 ingest` for the current embedder |
| embedding-service not ready: "sentence-transformers is not installed" | `uv pip install --python .venv\Scripts\python.exe -e "services/embedding-service[st]"` |
| Slow ingestion | expected on the CPU with bge-m3; use multilingual-e5-base, or raise `EMBED_BATCH_SIZE` |
| Containers cannot reach Ollama | by design (loopback). Use the native stack, or expose Ollama yourself (see section 0) |

## 9. Done-when checklist (P13)

- [ ] soak test passes with no driver resets (needs the monitors moved first)
- [ ] eval baseline recorded for both candidates in `eval/results/`
- [ ] winner set as `recommender` in `models.ollama.yaml`
- [x] switching back to mock works by config only (`-Mock`, or `models.yaml`)
