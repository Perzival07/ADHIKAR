"""OTP delivery. Pluggable: console (development only), smtp, or memory (tests)."""
from __future__ import annotations

import asyncio
import logging
import smtplib
from email.message import EmailMessage
from typing import Protocol

from .config import Settings

log = logging.getLogger("auth_service.email")


class EmailSender(Protocol):
    async def send_otp(self, to: str, code: str, purpose: str) -> None: ...


def _body(code: str, purpose: str) -> tuple[str, str]:
    action = "create your Haqdaar account" if purpose == "signup" else "sign in to Haqdaar"
    subject = "Your Haqdaar verification code"
    text = (f"Your code to {action} is {code}.\n\nIt expires in 5 minutes. Never share this code with anyone; "
            "Haqdaar staff will never ask for it.\n\nIf you did not request this, you can ignore this email.")
    return subject, text


class ConsoleSender:
    """Development only (production config refuses it): writes the code to the service log."""

    async def send_otp(self, to: str, code: str, purpose: str) -> None:
        log.warning("[DEV ONLY] OTP for %s (%s): %s", mask_email(to), purpose, code)


class MemorySender:
    def __init__(self) -> None:
        self.outbox: list[tuple[str, str, str]] = []

    async def send_otp(self, to: str, code: str, purpose: str) -> None:
        self.outbox.append((to, code, purpose))


class SmtpSender:
    def __init__(self, s: Settings) -> None:
        self.s = s

    def _send(self, to: str, code: str, purpose: str) -> None:
        subject, text = _body(code, purpose)
        msg = EmailMessage()
        msg["From"], msg["To"], msg["Subject"] = self.s.smtp_from, to, subject
        msg.set_content(text)
        with smtplib.SMTP(self.s.smtp_host, self.s.smtp_port, timeout=10) as smtp:
            if self.s.smtp_starttls:
                smtp.starttls()
            if self.s.smtp_username:
                smtp.login(self.s.smtp_username, self.s.smtp_password)
            smtp.send_message(msg)

    async def send_otp(self, to: str, code: str, purpose: str) -> None:
        await asyncio.to_thread(self._send, to, code, purpose)


def make_sender(s: Settings) -> EmailSender:
    if s.email_backend == "smtp":
        if not s.smtp_host:
            raise ValueError("AUTH_SMTP_HOST is required for the smtp email backend")
        return SmtpSender(s)
    if s.email_backend == "console":
        return ConsoleSender()
    if s.email_backend == "memory":
        return MemorySender()
    raise ValueError(f"unknown AUTH_EMAIL_BACKEND {s.email_backend!r}")


def mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    return f"{name[:1]}***@{domain}" if domain else "***"
