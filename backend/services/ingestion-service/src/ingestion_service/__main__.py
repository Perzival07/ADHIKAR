"""CLI:  python -m ingestion_service ingest [--path P] [--force] [--watch]"""
import argparse
import asyncio
import sys

from .config import get_settings
from .main import build_ingestor
from .watcher import watch_forever


async def clear_downstream_cache(settings, status) -> bool:
    """Best effort: a failure here must not fail the ingestion (cached answers expire on their own)."""
    changed = status.chunks_added or status.chunks_deleted
    if not (settings.cache_clear_url and changed and status.state == "done"):
        return False
    import httpx

    try:
        async with httpx.AsyncClient(timeout=10) as c:
            r = await c.post(settings.cache_clear_url, headers={"Authorization": f"Bearer {settings.cache_clear_token}"})
        print(f"cache clear: HTTP {r.status_code}")
        return r.status_code == 200
    except httpx.HTTPError as e:
        print(f"cache clear failed: {e.__class__.__name__}", file=sys.stderr)
        return False


async def _run(args) -> int:
    ingestor = build_ingestor(get_settings())
    try:
        st = await ingestor.run(args.path, args.force)
        print(st.model_dump_json(indent=2))
        await clear_downstream_cache(ingestor.s, st)
        if args.watch:
            await watch_forever(ingestor)
        return 0 if st.state == "done" else 1
    finally:
        await ingestor.embedder.aclose()


def main() -> None:
    p = argparse.ArgumentParser(prog="ingestion_service")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("ingest")
    i.add_argument("--path")
    i.add_argument("--force", action="store_true")
    i.add_argument("--watch", action="store_true")
    args = p.parse_args()
    sys.exit(asyncio.run(_run(args)))


if __name__ == "__main__":
    main()
