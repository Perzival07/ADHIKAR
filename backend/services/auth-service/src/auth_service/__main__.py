"""Operational CLI.

    python -m auth_service migrate         # alembic upgrade head (run as a Job before rollout)
    python -m auth_service gen-key         # print a new ES256 private key (store it in a Secret)
    python -m auth_service seed-demo       # development only
"""
from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path


def migrate(url: str | None = None) -> None:
    from alembic import command
    from alembic.config import Config

    from .config import get_settings

    root = Path(__file__).resolve().parent
    cfg = Config()
    cfg.set_main_option("script_location", str(root / "migrations"))
    cfg.set_main_option("sqlalchemy.url", url or get_settings().database_url)
    command.upgrade(cfg, "head")


def main() -> int:
    p = argparse.ArgumentParser(prog="auth_service")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("migrate")
    gk = sub.add_parser("gen-key")
    gk.add_argument("--base64", action="store_true", help="single-line output for env files / Kubernetes secrets")
    sub.add_parser("seed-demo")
    args = p.parse_args()
    if args.cmd == "migrate":
        migrate()
        print("migrations applied")
    elif args.cmd == "gen-key":
        from .security import generate_private_key_pem

        pem = generate_private_key_pem()
        if args.base64:
            import base64

            print(base64.b64encode(pem.encode()).decode())
        else:
            print(pem, end="")
    elif args.cmd == "seed-demo":
        from .config import get_settings
        from .db import make_engine, make_sessionmaker
        from .seed import seed_demo_users

        s = get_settings()
        if s.is_production:
            print("refusing to seed demo users in production", file=sys.stderr)
            return 1

        async def run():
            engine = make_engine(s.database_url)
            async with make_sessionmaker(engine)() as db:
                print(f"seeded {await seed_demo_users(db)} users")
            await engine.dispose()

        asyncio.run(run())
    return 0


if __name__ == "__main__":
    sys.exit(main())
