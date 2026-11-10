"""CLI:  python -m eval run --target URL --tag NAME   |   python -m eval compare A.json B.json"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import report, runner

HERE = Path(__file__).parent
DEFAULT_DOCS = HERE.parent / "data" / "scheme_docs"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="eval")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="run the golden set against a recommendation-service")
    r.add_argument("--target", default="http://localhost:8000")
    r.add_argument("--tag", required=True, help="name of this run, e.g. baseline-qwen3b or prompt-v2")
    r.add_argument("--golden", type=Path)
    r.add_argument("--docs", type=Path, default=DEFAULT_DOCS, help="documents folder (for the unknown-id check)")
    r.add_argument("--limit", type=int)
    r.add_argument("--timeout", type=float, default=180.0)
    r.add_argument("--out", type=Path)
    r.add_argument("--metrics-token", default="", help="bearer token for GET /metrics (RECO_METRICS_TOKEN), if the server requires one")
    r.add_argument("--min-recall10", type=float, help="exit 1 if recall@10 is below this")
    r.add_argument("--max-violation", type=float, help="exit 1 if violation_rate is above this")
    r.add_argument("--max-error", type=float, help="exit 1 if error_rate is above this")

    c = sub.add_parser("compare", help="markdown table comparing two result files")
    c.add_argument("a", type=Path)
    c.add_argument("b", type=Path)

    args = p.parse_args(argv)
    if args.cmd == "compare":
        print(report.compare(report.load(args.a), report.load(args.b)))
        return 0

    def progress(res):
        flag = "ok " if res.status == 200 and not res.violations and (res.recall10 in (None, 1.0)) else "!! "
        print(f"{flag}{res.id:<34} {res.mode or 'error':<10} {res.latency_ms:>7.0f} ms", file=sys.stderr)

    result = runner.run(args.target, args.tag, args.golden, args.docs, args.limit, args.timeout, progress,
                        metrics_token=args.metrics_token)
    out = args.out or HERE / "results" / f"{args.tag}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(report.summary(result))
    fails = report.failures(result)
    if fails:
        print("\nCases needing attention:\n" + "\n".join(fails))
    print(f"\nWrote {out}")

    m = result["metrics"]
    bad = []
    if args.min_recall10 is not None and (m["recall@10"] or 0) < args.min_recall10:
        bad.append(f"recall@10 {m['recall@10']} < {args.min_recall10}")
    if args.max_violation is not None and (m["violation_rate"] or 0) > args.max_violation:
        bad.append(f"violation_rate {m['violation_rate']} > {args.max_violation}")
    if args.max_error is not None and (m["error_rate"] or 0) > args.max_error:
        bad.append(f"error_rate {m['error_rate']} > {args.max_error}")
    if bad:
        print("THRESHOLDS FAILED: " + "; ".join(bad), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
