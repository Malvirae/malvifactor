from datetime import date, datetime, time
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum as SAEnum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Time,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class WeightSource(StrEnum):
    MANUAL = "manual"
    HEALTH_CONNECT = "health_connect"


def _enum_values(enum_cls: type[StrEnum]) -> list[str]:
    return [member.value for member in enum_cls]


class FoodLog(Base):
    """Daily food intake log entry."""

    __tablename__ = "food_logs"
    __table_args__ = (
        Index("ix_food_logs_user_date", "user_id", "logged_date"),
    )

    id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    logged_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    logged_time: Mapped[time] = mapped_column(Time, nullable=False)
    food_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("foods.id", ondelete="SET NULL"),
        nullable=True,
    )
    recipe_id: Mapped[UUID | None] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("recipes.id", ondelete="SET NULL"),
        nullable=True,
    )
    custom_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    quantity_g: Mapped[float] = mapped_column(Float, nullable=False)
    kcal: Mapped[float] = mapped_column(Float, nullable=False)
    protein_g: Mapped[float] = mapped_column(Float, nullable=False)
    fat_g: Mapped[float] = mapped_column(Float, nullable=False)
    carbs_g: Mapped[float] = mapped_column(Float, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class WeightLog(Base):
    """Body weight measurement with idempotency on (user_id, measured_at)."""

    __tablename__ = "weight_logs"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "measured_at",
            name="uq_weight_logs_user_measured_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    measured_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    body_fat_pct: Mapped[float | None] = mapped_column(Float, nullable=True)
    trend_weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[WeightSource] = mapped_column(
        SAEnum(WeightSource, name="weight_source_enum", values_callable=_enum_values),
        nullable=False,
        default=WeightSource.MANUAL,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class WeeklyCheckin(Base):
    """Weekly adaptive TDEE recalculation and macro target adjustment."""

    __tablename__ = "weekly_checkins"

    id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    checkin_date: Mapped[date] = mapped_column(Date, nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)

    avg_intake_kcal: Mapped[float] = mapped_column(Float, nullable=False)
    days_logged_count: Mapped[int] = mapped_column(Integer, nullable=False)
    start_trend_weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    end_trend_weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    calculated_tdee_kcal: Mapped[float] = mapped_column(Float, nullable=False)

    new_calorie_target: Mapped[float] = mapped_column(Float, nullable=False)
    new_protein_g: Mapped[float] = mapped_column(Float, nullable=False)
    new_fat_g: Mapped[float] = mapped_column(Float, nullable=False)
    new_carbs_g: Mapped[float] = mapped_column(Float, nullable=False)

    accepted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
