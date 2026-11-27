from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, model_validator


class LoginRequest(BaseModel):
    """Login credentials accepting either email or username."""

    email: EmailStr | None = None
    username: str | None = None
    password: str

    @model_validator(mode="after")
    def validate_identifier(self) -> "LoginRequest":
        if not self.email and not self.username:
            raise ValueError("Either 'email' or 'username' must be provided")
        return self


class RefreshRequest(BaseModel):
    """Refresh token payload."""

    refresh_token: str


class TokenResponse(BaseModel):
    """JWT access and refresh token pair."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    """Authenticated user public representation."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    username: str
    display_name: str
    is_active: bool
    created_at: datetime
