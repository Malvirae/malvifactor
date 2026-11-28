from datetime import date

from pydantic import BaseModel


class WeeklyNutritionDay(BaseModel):
    """Daily consumed and target macros for a single day of the calendar week."""

    date: date
    day_of_week: int  # 1 (Monday) .. 7 (Sunday)
    is_today: bool
    is_future: bool
    consumed_kcal: float
    consumed_protein_g: float
    consumed_fat_g: float
    consumed_carbs_g: float
    target_kcal: float
    target_protein_g: float
    target_fat_g: float
    target_carbs_g: float


class WeeklyNutritionTotals(BaseModel):
    """Exact 7-day sums of consumed and target macros."""

    consumed_kcal: float
    consumed_protein_g: float
    consumed_fat_g: float
    consumed_carbs_g: float
    target_kcal: float
    target_protein_g: float
    target_fat_g: float
    target_carbs_g: float


class WeeklyNutritionResponse(BaseModel):
    """Calendar week (Monday -> Sunday) nutrition overview for the Dashboard."""

    week_start: date
    week_end: date
    days: list[WeeklyNutritionDay]
    week_totals: WeeklyNutritionTotals
