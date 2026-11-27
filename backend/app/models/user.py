from datetime import date, datetime
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum as SAEnum,
    Float,
    ForeignKey,
    Integer,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Sex(StrEnum):
    MALE = "M"
    FEMALE = "F"


class GoalType(StrEnum):
    LOSE = "lose"
    MAINTAIN = "maintain"
    GAIN = "gain"


class ProteinPreference(StrEnum):
    MODERATE = "moderate"
    HIGH = "high"
    EXTRA_HIGH = "extra_high"


class DietStyle(StrEnum):
    BALANCED = "balanced"
    LOW_FAT = "low_fat"
    LOW_CARB = "low_carb"


def _enum_values(enum_cls: type[StrEnum]) -> list[str]:
    return [member.value for member in enum_cls]


class User(Base):
    """Application user account (restricted to couple accounts via CLI)."""

    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), primary_key=True, default=uuid4
    )
    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    username: Mapped[str] = mapped_column(
        String(64), unique=True, index=True, nullable=False
    )
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    profile: Mapped["UserProfile | None"] = relationship(
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )


class UserProfile(Base):
    """Physiological parameters, nutrition targets, and adaptive TDEE state."""

    __tablename__ = "user_profiles"

    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    sex: Mapped[Sex] = mapped_column(
        SAEnum(Sex, name="sex_enum", values_callable=_enum_values),
        nullable=False,
        default=Sex.MALE,
    )
    birth_date: Mapped[date] = mapped_column(
        Date, nullable=False, default=date(1995, 1, 1)
    )
    height_cm: Mapped[float] = mapped_column(Float, nullable=False, default=175.0)
    activity_level: Mapped[str] = mapped_column(
        String(32), nullable=False, default="moderate"
    )
    goal_type: Mapped[GoalType] = mapped_column(
        SAEnum(GoalType, name="goal_type_enum", values_callable=_enum_values),
        nullable=False,
        default=GoalType.MAINTAIN,
    )
    target_rate_kg_per_week: Mapped[float] = mapped_column(
        Float, nullable=False, default=0.0
    )
    protein_preference: Mapped[ProteinPreference] = mapped_column(
        SAEnum(
            ProteinPreference,
            name="protein_preference_enum",
            values_callable=_enum_values,
        ),
        nullable=False,
        default=ProteinPreference.HIGH,
    )
    diet_style: Mapped[DietStyle] = mapped_column(
        SAEnum(DietStyle, name="diet_style_enum", values_callable=_enum_values),
        nullable=False,
        default=DietStyle.BALANCED,
    )
    checkin_day: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    initial_tdee_kcal: Mapped[float] = mapped_column(
        Float, nullable=False, default=2000.0
    )
    current_tdee_kcal: Mapped[float] = mapped_column(
        Float, nullable=False, default=2000.0
    )
    current_calorie_target: Mapped[float] = mapped_column(
        Float, nullable=False, default=2000.0
    )
    current_protein_g: Mapped[float] = mapped_column(
        Float, nullable=False, default=150.0
    )
    current_fat_g: Mapped[float] = mapped_column(Float, nullable=False, default=65.0)
    current_carbs_g: Mapped[float] = mapped_column(
        Float, nullable=False, default=200.0
    )
    target_weight_kg: Mapped[float | None] = mapped_column(
        Float, nullable=True, default=None
    )
    onboarding_completed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    user: Mapped["User"] = relationship(back_populates="profile")
