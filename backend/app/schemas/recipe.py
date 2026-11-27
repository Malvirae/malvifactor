from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class RecipeIngredientInput(BaseModel):
    """Ingredient input line when creating or updating a recipe."""

    food_id: UUID
    quantity_g: float = Field(..., gt=0.0)


class RecipeIngredientDetail(BaseModel):
    """Detailed ingredient with computed macros for its quantity."""

    id: UUID
    food_id: UUID
    food_name: str
    food_brand: str | None
    quantity_g: float
    kcal: float
    protein_g: float
    fat_g: float
    carbs_g: float


class RecipeCreate(BaseModel):
    """Payload to create a shared or personal recipe."""

    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    servings_count: float = Field(default=1.0, gt=0.0)
    is_shared: bool = True
    final_weight_g: float | None = Field(default=None, gt=0.0)
    ingredients: list[RecipeIngredientInput] = Field(..., min_length=1)


class RecipeUpdate(BaseModel):
    """Payload to update a recipe and optionally replace its ingredients."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    servings_count: float | None = Field(default=None, gt=0.0)
    is_shared: bool | None = None
    final_weight_g: float | None = Field(default=None, gt=0.0)
    ingredients: list[RecipeIngredientInput] | None = Field(
        default=None, min_length=1
    )


class RecipeSummary(BaseModel):
    """Recipe summary without full ingredient breakdown."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None
    total_weight_g: float
    servings_count: float
    kcal_per_100g: float
    protein_per_100g: float
    fat_per_100g: float
    carbs_per_100g: float
    created_by_user_id: UUID
    is_shared: bool
    created_at: datetime
    updated_at: datetime


class RecipeResponse(RecipeSummary):
    """Full recipe detail including computed ingredient macros."""

    ingredients: list[RecipeIngredientDetail]
