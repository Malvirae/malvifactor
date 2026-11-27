from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class MacroSummary(BaseModel):
    """Calorie and macronutrient totals."""

    kcal: float
    protein_g: float
    fat_g: float
    carbs_g: float


class FoodLogCreate(BaseModel):
    """Create a food log from a food, a recipe, or a free quick-add entry."""

    logged_date: date
    logged_time: time
    food_id: UUID | None = None
    recipe_id: UUID | None = None
    custom_name: str | None = Field(default=None, min_length=1, max_length=255)
    quantity_g: float | None = Field(default=None, gt=0.0)
    kcal: float | None = Field(default=None, ge=0.0)
    protein_g: float | None = Field(default=None, ge=0.0)
    fat_g: float | None = Field(default=None, ge=0.0)
    carbs_g: float | None = Field(default=None, ge=0.0)

    @model_validator(mode="after")
    def validate_source(self) -> "FoodLogCreate":
        if self.food_id is not None and self.recipe_id is not None:
            raise ValueError("Provide either food_id or recipe_id, not both")

        if self.food_id is not None or self.recipe_id is not None:
            if self.quantity_g is None:
                raise ValueError(
                    "quantity_g is required when logging a food or recipe"
                )
        else:
            if (
                not self.custom_name
                or self.kcal is None
                or self.protein_g is None
                or self.fat_g is None
                or self.carbs_g is None
            ):
                raise ValueError(
                    "custom_name, kcal, protein_g, fat_g, and carbs_g are required "
                    "for a free quick-add entry"
                )
        return self


class FoodLogUpdate(BaseModel):
    """Update a food log entry."""

    logged_date: date | None = None
    logged_time: time | None = None
    food_id: UUID | None = None
    custom_name: str | None = Field(default=None, min_length=1, max_length=255)
    quantity_g: float | None = Field(default=None, gt=0.0)
    kcal: float | None = Field(default=None, ge=0.0)
    protein_g: float | None = Field(default=None, ge=0.0)
    fat_g: float | None = Field(default=None, ge=0.0)
    carbs_g: float | None = Field(default=None, ge=0.0)


class FoodLogItem(BaseModel):
    """Serialized food log entry enriched with food/recipe display info."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    logged_date: date
    logged_time: time
    food_id: UUID | None
    recipe_id: UUID | None
    custom_name: str | None
    display_name: str
    brand: str | None
    quantity_g: float
    kcal: float
    protein_g: float
    fat_g: float
    carbs_g: float
    created_at: datetime


class DayLogsResponse(BaseModel):
    """Daily timeline with totals, targets, and remaining macros."""

    date: date
    entries: list[FoodLogItem]
    totals: MacroSummary
    targets: MacroSummary
    remaining: MacroSummary


class FoodLogCopyRequest(BaseModel):
    """Duplicate selected log entries or a source date range to a target date."""

    log_ids: list[UUID] | None = None
    source_date: date | None = None
    start_time: time | None = None
    end_time: time | None = None
    target_date: date
    target_time: time | None = None

    @model_validator(mode="after")
    def validate_selection(self) -> "FoodLogCopyRequest":
        if not self.log_ids and self.source_date is None:
            raise ValueError("Provide either log_ids or source_date")
        return self


class DaySummaryItem(BaseModel):
    """Daily aggregated macros over a date range."""

    date: date
    kcal: float
    protein_g: float
    fat_g: float
    carbs_g: float
    entries_count: int


class FoodLogMoveRequest(BaseModel):
    """Move selected log entries to a target date and optional time."""

    log_ids: list[UUID] = Field(..., min_length=1)
    target_date: date
    target_time: time | None = None


class FoodLogBatchDeleteRequest(BaseModel):
    """Batch delete selected log entries."""

    log_ids: list[UUID] = Field(..., min_length=1)


class FoodLogBatchDeleteResponse(BaseModel):
    """Number of deleted log entries."""

    deleted_count: int
