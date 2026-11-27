from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class CheckinPreviewResponse(BaseModel):
    """Non-persisted preview of the weekly adaptive TDEE check-in."""

    checkin_date: date
    period_start: date
    period_end: date
    avg_intake_kcal: float
    days_logged_count: int
    start_trend_weight_kg: float
    end_trend_weight_kg: float
    previous_tdee_kcal: float
    calculated_tdee_kcal: float
    tdee_delta_kcal: float
    new_calorie_target: float
    new_protein_g: float
    new_fat_g: float
    new_carbs_g: float
    confidence: Literal["low", "medium", "high"]
    is_due: bool


class WeeklyCheckinResponse(BaseModel):
    """Persisted weekly check-in record."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    checkin_date: date
    period_start: date
    period_end: date
    avg_intake_kcal: float
    days_logged_count: int
    start_trend_weight_kg: float
    end_trend_weight_kg: float
    calculated_tdee_kcal: float
    new_calorie_target: float
    new_protein_g: float
    new_fat_g: float
    new_carbs_g: float
    accepted: bool
    created_at: datetime


class AnalyticsPoint(BaseModel):
    """Daily time-series point for charts."""

    date: date
    intake_kcal: float
    target_kcal: float
    weight_kg: float | None
    trend_weight_kg: float | None
    estimated_tdee_kcal: float
