from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

Purpose = Literal["signup", "login"]


def _norm_email(v: str) -> str:
    return v.strip().lower()


class OtpRequest(BaseModel):
    email: EmailStr
    purpose: Purpose = "login"
    _n = field_validator("email")(lambda cls, v: _norm_email(v))


class OtpRequested(BaseModel):
    status: Literal["accepted"] = "accepted"
    message: str = "If the address can receive a code, one has been sent."
    resend_after: int


class SignupRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    code: str = Field(..., pattern=r"^\d{6}$")
    password: str = Field(..., min_length=1, max_length=128)
    name: str = Field(..., min_length=1, max_length=120)
    state: str = Field("All India", max_length=64)
    socialCategory: str = Field("General", max_length=16)
    occupation: str = Field("Citizen", max_length=64)
    _n = field_validator("email")(lambda cls, v: _norm_email(v))


class PasswordLogin(BaseModel):
    identifier: str = Field(..., min_length=3, max_length=254, description="email or phone number")
    password: str = Field(..., min_length=1, max_length=128)


class OtpLogin(BaseModel):
    email: EmailStr
    code: str = Field(..., pattern=r"^\d{6}$")
    _n = field_validator("email")(lambda cls, v: _norm_email(v))


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=200)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str | None
    phone: str | None
    name: str
    state: str
    socialCategory: str = Field(validation_alias="social_category")
    occupation: str
    profile: dict[str, Any] | None
    isVerified: bool = Field(validation_alias="is_verified")
    createdAt: datetime = Field(validation_alias="created_at")


class TokenPair(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    refresh_token: str
    refresh_expires_in: int
    user: UserOut


class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(None, min_length=1, max_length=120)
    state: str | None = Field(None, max_length=64)
    socialCategory: str | None = Field(None, max_length=16)
    occupation: str | None = Field(None, max_length=64)
    profile: dict[str, Any] | None = None  # saved eligibility answers; send {} to clear


class ErrorOut(BaseModel):
    detail: str
