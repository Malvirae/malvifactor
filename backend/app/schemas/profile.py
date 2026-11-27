from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.user import DietStyle, GoalType, ProteinPreference, Sex

ActivityLevel = Literal[
    "sedentary",
    "light",
    "moderate",
    "active",
    "very_active",
]

NeatLevel = Literal[
    "sedentary_desk",
    "lightly_active_daily",
    "standing_active",
    "very_mobile",
]

WorkoutType = Literal["strength", "cardio", "mixed"]


class ProfileResponse(BaseModel):
    """User physiological profile and current nutrition targets."""

    model_config = ConfigDict(from_attributes=True)

    user_id: UUID
    sex: Sex
    birth_date: date
    height_cm: float
    activity_level: str
    goal_type: GoalType
    target_rate_kg_per_week: float
    protein_preference: ProteinPreference
    diet_style: DietStyle
    checkin_day: int
    initial_tdee_kcal: float
    current_tdee_kcal: float
    current_calorie_target: float
    current_protein_g: float
    current_fat_g: float
    current_carbs_g: float
    target_weight_kg: float | None = None
    onboarding_completed: bool = False
    updated_at: datetime


class ProfileUpdate(BaseModel):
    """Payload to update physiological parameters and optionally recalculate TDEE/macros."""

    display_name: str | None = Field(default=None, min_length=1, max_length=120)
    sex: Sex | None = None
    birth_date: date | None = None
    height_cm: float | None = Field(default=None, gt=50.0, lt=300.0)
    activity_level: ActivityLevel | None = None
    goal_type: GoalType | None = None
    target_rate_kg_per_week: float | None = Field(default=None, ge=-2.0, le=2.0)
    protein_preference: ProteinPreference | None = None
    diet_style: DietStyle | None = None
    checkin_day: int | None = Field(default=None, ge=0, le=6)
    target_weight_kg: float | None = Field(default=None, gt=20.0, lt=350.0)
    onboarding_completed: bool | None = None

    recalculate_targets: bool = False
    reference_weight_kg: float | None = Field(default=None, gt=20.0, lt=350.0)

    weight_kg: float | None = Field(default=None, gt=20.0, lt=350.0)
    body_fat_pct: float | None = Field(default=None, ge=5.0, le=60.0)
    neat_level: NeatLevel | None = None
    workouts_per_week: int | None = Field(default=None, ge=0, le=7)
    workout_type: WorkoutType | None = None
    manual_initial_tdee_kcal: int | None = Field(default=None, gt=500, lt=10000)

    initial_tdee_kcal: float | None = Field(default=None, gt=500.0, lt=10000.0)
    current_tdee_kcal: float | None = Field(default=None, gt=500.0, lt=10000.0)
    current_calorie_target: float | None = Field(default=None, gt=500.0, lt=10000.0)
    current_protein_g: float | None = Field(default=None, ge=0.0, lt=1000.0)
    current_fat_g: float | None = Field(default=None, ge=0.0, lt=1000.0)
    current_carbs_g: float | None = Field(default=None, ge=0.0, lt=1500.0)
