"""Stability soak test for a real local LLM (plan P13 step 6).

Sends SEQUENTIAL recommendation requests (cache bypassed, so every one hits the LLM) for a fixed duration while
sampling the GPU with nvidia-smi every 10 s. Writes eval/results/soak-<tag>.json and eval/results/soak-<tag>.gpu.csv.

    .venv/Scripts/python scripts/soak_test.py --tag qwen25-3b --minutes 30 [--target http://127.0.0.1:8000]

PASS criteria (printed at the end): no HTTP errors, no nvidia-smi failures (a driver reset makes it fail),
rag mode on every request (no rules-only fallbacks), peak VRAM <= --max-vram-mb (5500 by default), p95 recorded.
"""
from __future__ import annotations

import argparse
import csv
import json
import shutil
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

import httpx

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
from eval.golden import load_golden

GPU_FIELDS = "timestamp,index,name,memory.used,memory.total,temperature.gpu,power.draw,utilization.gpu"


class GpuLogger(threading.Thread):
    def __init__(self, path: Path, every: float = 10.0):
        super().__init__(daemon=True)
        self.path, self.every, self.stop = path, every, threading.Event()
        self.rows: list[dict[str, str]] = []
        self.failures = 0
        self.available = shutil.which("nvidia-smi") is not None

    def sample(self) -> None:
        try:
            out = subprocess.run(
                ["nvidia-smi", f"--query-gpu={GPU_FIELDS}", "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=10, check=True,
            ).stdout
        except (subprocess.SubprocessError, OSError):
            self.failures += 1
            return
        for line in out.strip().splitlines():
            vals = [v.strip() for v in line.split(",")]
            self.rows.append(dict(zip(GPU_FIELDS.split(","), vals, strict=False)))

    def run(self) -> None:
        if not self.available:
            return
        while not self.stop.is_set():
            self.sample()
            self.stop.wait(self.every)
        with self.path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=GPU_FIELDS.split(","))
            w.writeheader()
            w.writerows(self.rows)

    def peak(self, field: str, index: str | None = None) -> float | None:
        vals = []
        for r in self.rows:
            if index is not None and r.get("index") != index:
                continue
            try:
                vals.append(float(r[field]))
            except (KeyError, ValueError):
                continue
        return max(vals) if vals else None


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", default="http://127.0.0.1:8000")
    p.add_argument("--tag", required=True)
    p.add_argument("--minutes", type=float, default=30.0)
    p.add_argument("--timeout", type=float, default=240.0)
    p.add_argument("--gpu-index", default="0", help="nvidia-smi index of the inference GPU for the VRAM check")
    p.add_argument("--max-vram-mb", type=float, default=5500.0)
    p.add_argument("--language-mix", default="en,hi", help="cycle requests through these languages")
    args = p.parse_args()

    cases = load_golden()
    langs = [x.strip() for x in args.language_mix.split(",") if x.strip()]
    out_dir = BACKEND / "eval" / "results"
    out_dir.mkdir(parents=True, exist_ok=True)
    gpu = GpuLogger(out_dir / f"soak-{args.tag}.gpu.csv")
    gpu.start()

    results: list[dict] = []
    t_end = time.monotonic() + args.minutes * 60
    i = 0
    with httpx.Client(timeout=args.timeout) as client:
        while time.monotonic() < t_end:
            case = cases[i % len(cases)]
            lang = langs[i % len(langs)]
            body = {"profile": case.profile, "language": lang, "top_n": case.top_n, "include_citations": True}
            t0 = time.perf_counter()
            rec: dict = {"i": i, "case": case.id, "language": lang}
            try:
                r = client.post(f"{args.target}/v1/recommendations", json=body, headers={"Cache-Control": "no-cache"})
                rec.update(status=r.status_code, ms=(time.perf_counter() - t0) * 1000)
                if r.status_code == 200:
                    d = r.json()
                    rec.update(mode=d.get("mode"), fallback_reason=d.get("fallback_reason"), n=len(d.get("recommendations", [])))
                else:
                    rec["error"] = r.text[:200]
            except httpx.HTTPError as e:
                rec.update(status=0, ms=(time.perf_counter() - t0) * 1000, error=f"{e.__class__.__name__}: {e}")
            results.append(rec)
            ok = rec.get("status") == 200 and rec.get("mode") == "rag"
            what = rec.get("mode") or rec.get("error", "")
            print(f"{'ok ' if ok else '!! '}{i:>4} {case.id:<32} {lang} {what!s:<14} {rec['ms']:>8.0f} ms", file=sys.stderr)
            i += 1
    gpu.stop.set()
    gpu.join(timeout=15)

    lat = sorted(r["ms"] for r in results if r.get("status") == 200)

    def q(pct: float) -> float | None:
        return lat[min(len(lat) - 1, round(pct * (len(lat) - 1)))] if lat else None

    errors = [r for r in results if r.get("status") != 200]
    fallbacks = [r for r in results if r.get("status") == 200 and r.get("mode") != "rag"]
    peak_vram = gpu.peak("memory.used", args.gpu_index)
    summary = {
        "tag": args.tag, "target": args.target, "minutes": args.minutes, "requests": len(results),
        "errors": len(errors), "rules_only_fallbacks": len(fallbacks),
        "fallback_reasons": sorted({str(r.get("fallback_reason")) for r in fallbacks}),
        "latency_ms": {"p50": q(0.5), "p95": q(0.95), "max": lat[-1] if lat else None,
                       "mean": statistics.fmean(lat) if lat else None},
        "gpu": {"available": gpu.available, "samples": len(gpu.rows), "nvidia_smi_failures": gpu.failures,
                "peak_vram_mb": peak_vram, "peak_temp_c": gpu.peak("temperature.gpu", args.gpu_index),
                "peak_power_w": gpu.peak("power.draw", args.gpu_index)},
    }
    checks = {
        "no_http_errors": len(errors) == 0,
        "no_fallbacks": len(fallbacks) == 0,
        "no_nvidia_smi_failures": gpu.failures == 0,
        "vram_within_budget": (peak_vram is None) or (peak_vram <= args.max_vram_mb),
    }
    summary["checks"] = checks
    summary["pass"] = all(checks.values())
    out = out_dir / f"soak-{args.tag}.json"
    out.write_text(json.dumps({"summary": summary, "requests": results}, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=1))
    print(f"\n{'PASS' if summary['pass'] else 'FAIL'}  ->  {out}")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
