from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.food import FoodSource


class FoodBase(BaseModel):
    """Shared nutritional attributes for a food item."""

    name: str = Field(..., min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    external_id: str | None = Field(default=None, max_length=128)
    serving_size_g: float = Field(default=100.0, gt=0.0)
    serving_label: str | None = Field(default=None, max_length=100)
    kcal_per_100g: float = Field(..., ge=0.0)
    protein_per_100g: float = Field(..., ge=0.0)
    fat_per_100g: float = Field(..., ge=0.0)
    carbs_per_100g: float = Field(..., ge=0.0)
    fiber_per_100g: float = Field(default=0.0, ge=0.0)


class FoodCreate(FoodBase):
    """Payload to create a custom food."""


class FoodUpdate(BaseModel):
    """Payload to update an existing custom food."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    external_id: str | None = Field(default=None, max_length=128)
    serving_size_g: float | None = Field(default=None, gt=0.0)
    serving_label: str | None = Field(default=None, max_length=100)
    kcal_per_100g: float | None = Field(default=None, ge=0.0)
    protein_per_100g: float | None = Field(default=None, ge=0.0)
    fat_per_100g: float | None = Field(default=None, ge=0.0)
    carbs_per_100g: float | None = Field(default=None, ge=0.0)
    fiber_per_100g: float | None = Field(default=None, ge=0.0)


class FoodCustomizeRequest(BaseModel):
    """Payload to customize or override a food's 100g nutrition values."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    serving_size_g: float | None = Field(default=None, gt=0.0)
    serving_label: str | None = Field(default=None, max_length=100)
    kcal_per_100g: float | None = Field(default=None, ge=0.0)
    protein_per_100g: float | None = Field(default=None, ge=0.0)
    fat_per_100g: float | None = Field(default=None, ge=0.0)
    carbs_per_100g: float | None = Field(default=None, ge=0.0)
    fiber_per_100g: float | None = Field(default=None, ge=0.0)


class FoodResponse(FoodBase):
    """Serialized food representation."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    source: FoodSource
    external_id: str | None
    created_by_user_id: UUID | None
    created_at: datetime
