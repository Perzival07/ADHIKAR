from __future__ import annotations

import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from auth_service.db import Base

config = context.config
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(url=config.get_main_option("sqlalchemy.url"), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


MIGRATION_LOCK_ID = 7_441_201  # arbitrary constant shared by every auth-service pod


def _run(connection) -> None:
    # Several pods may start at once (each runs migrations in an init container). On Postgres a
    # transaction-scoped advisory lock makes them take turns; the lock is released when the migration
    # transaction commits, and the next pod then finds the schema already at head and does nothing.
    if connection.dialect.name == "postgresql":
        connection.exec_driver_sql(f"SELECT pg_advisory_xact_lock({MIGRATION_LOCK_ID})")
    context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    engine = create_async_engine(config.get_main_option("sqlalchemy.url"))
    # engine.begin(): one transaction around lock + DDL, COMMITTED on success. (A bare connect() would roll the
    # DDL back on close, because executing the lock statement auto-begins a transaction Alembic then joins.)
    async with engine.begin() as conn:
        await conn.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
