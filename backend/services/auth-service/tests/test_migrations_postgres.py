"""Migrations against a REAL Postgres (transactional DDL + advisory lock). Skipped unless AUTH_TEST_POSTGRES_URL is set;
CI provides a Postgres service. Regression test: the lock statement once made Alembic's DDL roll back silently."""
import asyncio
import os
import subprocess
import sys

import pytest

URL = os.environ.get("AUTH_TEST_POSTGRES_URL", "")
pytestmark = pytest.mark.skipif(not URL, reason="set AUTH_TEST_POSTGRES_URL=postgresql+asyncpg://... to run")


async def _tables():
    import asyncpg

    conn = await asyncpg.connect(URL.replace("postgresql+asyncpg", "postgresql"))
    try:
        await conn.execute("SELECT 1")
        tables = {r["tablename"] for r in await conn.fetch("select tablename from pg_tables where schemaname='public'")}
        version = await conn.fetchval("select version_num from alembic_version") if "alembic_version" in tables else None
        return tables, version
    finally:
        await conn.close()


async def _reset():
    import asyncpg

    conn = await asyncpg.connect(URL.replace("postgresql+asyncpg", "postgresql"))
    try:
        await conn.execute("drop schema public cascade; create schema public;")
    finally:
        await conn.close()


def test_concurrent_migrations_commit_exactly_once():
    asyncio.run(_reset())
    env = {**os.environ, "AUTH_DATABASE_URL": URL}
    procs = [subprocess.Popen([sys.executable, "-m", "auth_service", "migrate"], env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) for _ in range(3)]
    results = [p.communicate(timeout=120) + (p.returncode,) for p in procs]
    assert all(rc == 0 for _, _, rc in results), results
    tables, version = asyncio.run(_tables())
    assert {"users", "otp_challenges", "refresh_tokens", "alembic_version"} <= tables
    assert version == "0001"
