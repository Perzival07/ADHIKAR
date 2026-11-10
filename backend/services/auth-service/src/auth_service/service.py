"""Account logic. Every failure path returns the same generic error so callers cannot enumerate accounts."""
from __future__ import annotations

import logging
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .config import Settings
from .db import OtpChallenge, RefreshToken, User
from .email import EmailSender, mask_email
from .schemas import SignupRequest, UserOut, UserUpdate
from .security import (
    SigningKey,
    hash_password,
    hash_refresh,
    new_otp,
    new_refresh_token,
    otp_hash,
    verify_password,
)

log = logging.getLogger("auth_service")


class AuthError(Exception):
    """Maps to an HTTP status; `detail` is safe to show to the client."""

    def __init__(self, status: int, detail: str, retry_after: int | None = None):
        super().__init__(detail)
        self.status, self.detail, self.retry_after = status, detail, retry_after


INVALID_CREDENTIALS = AuthError(401, "Invalid credentials.")
INVALID_CODE = AuthError(400, "The code is invalid or has expired. Request a new one.")


def now() -> datetime:
    return datetime.now(UTC)


def aware(dt: datetime | None) -> datetime | None:
    """SQLite returns naive datetimes; treat them as UTC."""
    return dt.replace(tzinfo=UTC) if dt is not None and dt.tzinfo is None else dt


class AuthService:
    def __init__(self, s: Settings, key: SigningKey, sender: EmailSender, otp_secret: str):
        self.s, self.key, self.sender, self.otp_secret = s, key, sender, otp_secret

    # ---------------------------------------------------------------- OTP
    async def request_otp(self, db: AsyncSession, email: str, purpose: str) -> int:
        """Always behaves the same whether or not the account exists. Returns seconds until resend is allowed."""
        t = now()
        recent = (await db.execute(
            select(OtpChallenge).where(OtpChallenge.email == email, OtpChallenge.purpose == purpose,
                                       OtpChallenge.created_at > t - timedelta(hours=1))
            .order_by(OtpChallenge.created_at.desc())
        )).scalars().all()
        if recent:
            wait = self.s.otp_resend_cooldown - int((t - aware(recent[0].created_at)).total_seconds())
            if wait > 0:
                raise AuthError(429, "Please wait before requesting another code.", retry_after=wait)
        if len(recent) >= self.s.otp_max_per_hour:
            raise AuthError(429, "Too many codes requested. Try again later.", retry_after=3600)

        user = await self._user_by_email(db, email)
        should_send = (purpose == "signup" and user is None) or (purpose == "login" and user is not None and user.is_active)
        code = new_otp()
        # record a challenge either way so cooldowns/limits don't reveal whether the account exists
        await db.execute(update(OtpChallenge).where(OtpChallenge.email == email, OtpChallenge.purpose == purpose,
                                                    OtpChallenge.consumed_at.is_(None)).values(consumed_at=t))
        # when nothing is sent, store a hash nobody can match (an unguessable random secret)
        stored = otp_hash(self.otp_secret, email, purpose, code if should_send else secrets.token_hex(16))
        db.add(OtpChallenge(email=email, purpose=purpose, code_hash=stored,
                            attempts_left=self.s.otp_attempts, expires_at=t + timedelta(seconds=self.s.otp_ttl), created_at=t))
        await db.commit()
        if should_send:
            await self.sender.send_otp(email, code, purpose)
            log.info("otp sent", extra={"fields": {"to": mask_email(email), "purpose": purpose}})
        return self.s.otp_resend_cooldown

    async def _consume_otp(self, db: AsyncSession, email: str, purpose: str, code: str) -> None:
        t = now()
        ch = (await db.execute(
            select(OtpChallenge).where(OtpChallenge.email == email, OtpChallenge.purpose == purpose, OtpChallenge.consumed_at.is_(None))
            .order_by(OtpChallenge.created_at.desc()).limit(1)
        )).scalar_one_or_none()
        if ch is None or aware(ch.expires_at) < t or ch.attempts_left <= 0:
            raise INVALID_CODE
        if otp_hash(self.otp_secret, email, purpose, code) != ch.code_hash:
            ch.attempts_left -= 1
            await db.commit()
            raise INVALID_CODE
        ch.consumed_at = t
        await db.flush()

    # ---------------------------------------------------------------- accounts
    async def _user_by_email(self, db: AsyncSession, email: str) -> User | None:
        return (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()

    async def signup(self, db: AsyncSession, req: SignupRequest) -> tuple[User, str, str]:
        if len(req.password) < self.s.password_min_length:
            raise AuthError(422, f"Password must be at least {self.s.password_min_length} characters.")
        await self._consume_otp(db, req.email, "signup", req.code)
        if await self._user_by_email(db, req.email):
            raise INVALID_CODE  # the code could only have been issued if no account existed; stay generic
        user = User(email=req.email, password_hash=hash_password(req.password), name=req.name.strip(), state=req.state,
                    social_category=req.socialCategory, occupation=req.occupation, is_verified=True)
        db.add(user)
        await db.flush()
        access, refresh = await self._issue(db, user)
        await db.commit()
        return user, access, refresh

    async def login_password(self, db: AsyncSession, identifier: str, password: str) -> tuple[User, str, str]:
        ident = identifier.strip().lower()
        user = (await db.execute(select(User).where((User.email == ident) | (User.phone == ident)))).scalar_one_or_none()
        t = now()
        if user is not None and aware(user.locked_until) and aware(user.locked_until) > t:
            verify_password(None, password)  # same cost as a real attempt
            raise AuthError(429, "Too many failed attempts. Try again later or sign in with a code.",
                            retry_after=int((aware(user.locked_until) - t).total_seconds()))
        ok = verify_password(user.password_hash if user else None, password)
        if user is None or not ok or not user.is_active:
            if user is not None:
                user.failed_logins += 1
                if user.failed_logins >= self.s.max_failed_logins:
                    user.locked_until = t + timedelta(seconds=self.s.lockout_seconds)
                    user.failed_logins = 0
                await db.commit()
            raise INVALID_CREDENTIALS
        user.failed_logins, user.locked_until = 0, None
        access, refresh = await self._issue(db, user)
        await db.commit()
        return user, access, refresh

    async def login_otp(self, db: AsyncSession, email: str, code: str) -> tuple[User, str, str]:
        await self._consume_otp(db, email, "login", code)
        user = await self._user_by_email(db, email)
        if user is None or not user.is_active:
            raise INVALID_CODE
        user.failed_logins, user.locked_until = 0, None
        access, refresh = await self._issue(db, user)
        await db.commit()
        return user, access, refresh

    # ---------------------------------------------------------------- tokens
    async def _issue(self, db: AsyncSession, user: User, family: uuid.UUID | None = None) -> tuple[str, str]:
        access = self.key.issue(str(user.id), self.s.jwt_issuer, self.s.jwt_audience, self.s.access_token_ttl)
        token, digest = new_refresh_token()
        db.add(RefreshToken(user_id=user.id, family_id=family or uuid.uuid4(), token_hash=digest,
                            expires_at=now() + timedelta(seconds=self.s.refresh_token_ttl)))
        return access, token

    async def refresh(self, db: AsyncSession, token: str) -> tuple[User, str, str]:
        row = (await db.execute(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(token)))).scalar_one_or_none()
        if row is None:
            raise INVALID_CREDENTIALS
        if row.revoked_at is not None:
            # A rotated-away token was replayed: assume theft and end every session of that login.
            await db.execute(update(RefreshToken).where(RefreshToken.family_id == row.family_id, RefreshToken.revoked_at.is_(None))
                             .values(revoked_at=now()))
            await db.commit()
            log.warning("refresh token reuse detected; session family revoked", extra={"fields": {"user": str(row.user_id)}})
            raise INVALID_CREDENTIALS
        if aware(row.expires_at) < now():
            raise INVALID_CREDENTIALS
        user = await db.get(User, row.user_id)
        if user is None or not user.is_active:
            raise INVALID_CREDENTIALS
        row.revoked_at = now()
        access, refresh = await self._issue(db, user, family=row.family_id)
        await db.commit()
        return user, access, refresh

    async def logout(self, db: AsyncSession, token: str) -> None:
        await db.execute(update(RefreshToken).where(RefreshToken.token_hash == hash_refresh(token), RefreshToken.revoked_at.is_(None))
                         .values(revoked_at=now()))
        await db.commit()

    async def logout_all(self, db: AsyncSession, user_id: uuid.UUID) -> None:
        await db.execute(update(RefreshToken).where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
                         .values(revoked_at=now()))
        await db.commit()

    # ---------------------------------------------------------------- profile
    async def update_user(self, db: AsyncSession, user: User, upd: UserUpdate) -> User:
        if upd.name is not None:
            user.name = upd.name.strip()
        if upd.state is not None:
            user.state = upd.state
        if upd.socialCategory is not None:
            user.social_category = upd.socialCategory
        if upd.occupation is not None:
            user.occupation = upd.occupation
        if upd.profile is not None:
            user.profile = upd.profile or None
        await db.commit()
        await db.refresh(user)
        return user

    async def delete_user(self, db: AsyncSession, user: User) -> None:
        await db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
        if user.email:
            await db.execute(delete(OtpChallenge).where(OtpChallenge.email == user.email))
        await db.delete(user)
        await db.commit()

    @staticmethod
    def user_out(user: User) -> UserOut:
        return UserOut.model_validate(user)
