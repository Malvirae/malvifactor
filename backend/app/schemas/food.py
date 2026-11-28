from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.food import FoodSource


class FoodBase(BaseModel):
    """Shared nutritional attributes for a food item."""

    name: str = Field(..., min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    stores: str | None = Field(default=None, max_length=255)
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
    stores: str | None = Field(default=None, max_length=255)
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
    stores: str | None = Field(default=None, max_length=255)
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
    source: str
    category: str | None = None
    external_id: str | None
    created_by_user_id: UUID | None
    created_at: datetime
    last_quantity_g: float | None = None
    servings: float | None = None
    total_weight_g: float | None = None
    serving_weight_g: float | None = None
    kcal_per_serving: float | None = None
    protein_per_serving: float | None = None
    fat_per_serving: float | None = None
    carbs_per_serving: float | None = None


class FoodSuggestionItem(BaseModel):
    """Contextual suggestion or recent food/recipe item with remembered quantity."""

    id: UUID
    item_type: Literal["standard", "custom", "recipe", "quick_add"]
    source: str
    category: str | None = None
    name: str
    brand: str | None = None
    stores: str | None = None
    serving_size_g: float
    serving_label: str | None = None
    kcal_per_100g: float
    protein_per_100g: float
    fat_per_100g: float
    carbs_per_100g: float
    fiber_per_100g: float = 0.0
    last_quantity_g: float
    last_serving_label: str | None = None
    preview_kcal: float
    preview_protein_g: float
    preview_fat_g: float
    preview_carbs_g: float
    last_logged_at: datetime
    times_logged_at_hour: int = 0
    servings: float | None = None
    total_weight_g: float | None = None
    serving_weight_g: float | None = None
    kcal_per_serving: float | None = None
    protein_per_serving: float | None = None
    fat_per_serving: float | None = None
    carbs_per_serving: float | None = None


class FoodSuggestionsResponse(BaseModel):
    """Time-windowed habitual picks and recent foods/recipes."""

    target_hour: int
    time_picks: list[FoodSuggestionItem]
    recent_foods: list[FoodSuggestionItem]
