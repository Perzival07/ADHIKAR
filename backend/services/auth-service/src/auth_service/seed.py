"""Development-only demo accounts (the same ones the app used to ship with). Refused in production."""
from __future__ import annotations

import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import User
from .security import hash_password

log = logging.getLogger("auth_service")

DEMO = [
    {"email": "citizen@adhikar.gov.in", "phone": None, "name": "Rajesh Sharma", "state": "Uttar Pradesh",
     "social_category": "OBC", "occupation": "Farmer"},
    {"email": None, "phone": "9876543210", "name": "Priya Patel", "state": "Gujarat",
     "social_category": "General", "occupation": "Student"},
]
DEMO_PASSWORD = "password123"


async def seed_demo_users(db: AsyncSession) -> int:
    n = 0
    for d in DEMO:
        cond = (User.email == d["email"]) if d["email"] else (User.phone == d["phone"])
        if (await db.execute(select(User).where(cond))).scalar_one_or_none():
            continue
        db.add(User(**d, password_hash=hash_password(DEMO_PASSWORD), is_verified=True))
        n += 1
    await db.commit()
    if n:
        log.warning("seeded %d DEMO users (development only)", n)
    return n
