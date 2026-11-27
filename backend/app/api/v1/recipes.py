from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.food import Food, Recipe, RecipeIngredient
from app.models.user import User
from app.schemas.recipe import (
    RecipeCreate,
    RecipeIngredientDetail,
    RecipeIngredientInput,
    RecipeResponse,
    RecipeSummary,
    RecipeUpdate,
)

router = APIRouter(prefix="/recipes", tags=["recipes"])


async def _load_foods_map(
    db: AsyncSession,
    food_ids: list[UUID],
) -> dict[UUID, Food]:
    unique_ids = list(dict.fromkeys(food_ids))
    result = await db.execute(select(Food).where(Food.id.in_(unique_ids)))
    foods_map = {food.id: food for food in result.scalars().all()}
    missing = [str(fid) for fid in unique_ids if fid not in foods_map]
    if missing:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Aliments introuvables : {', '.join(missing)}",
        )
    return foods_map


def _compute_recipe_nutrition(
    ingredients_input: list[RecipeIngredientInput],
    foods_map: dict[UUID, Food],
    final_weight_g: float | None,
) -> tuple[float, float, float, float, float]:
    """Compute total weight and per-100g macros from ingredient lines."""
    raw_weight = sum(item.quantity_g for item in ingredients_input)
    total_weight_g = final_weight_g if final_weight_g is not None else raw_weight
    if total_weight_g <= 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Le poids total de la recette doit être strictement positif",
        )

    total_kcal = 0.0
    total_protein = 0.0
    total_fat = 0.0
    total_carbs = 0.0

    for item in ingredients_input:
        food = foods_map[item.food_id]
        factor = item.quantity_g / 100.0
        total_kcal += food.kcal_per_100g * factor
        total_protein += food.protein_per_100g * factor
        total_fat += food.fat_per_100g * factor
        total_carbs += food.carbs_per_100g * factor

    scale = 100.0 / total_weight_g
    return (
        round(total_weight_g, 2),
        round(total_kcal * scale, 2),
        round(total_protein * scale, 2),
        round(total_fat * scale, 2),
        round(total_carbs * scale, 2),
    )


def _serialize_recipe(recipe: Recipe) -> RecipeResponse:
    ingredients_detail: list[RecipeIngredientDetail] = []
    for ing in recipe.ingredients:
        factor = ing.quantity_g / 100.0
        ingredients_detail.append(
            RecipeIngredientDetail(
                id=ing.id,
                food_id=ing.food_id,
                food_name=ing.food.name,
                food_brand=ing.food.brand,
                quantity_g=ing.quantity_g,
                kcal=round(ing.food.kcal_per_100g * factor, 2),
                protein_g=round(ing.food.protein_per_100g * factor, 2),
                fat_g=round(ing.food.fat_per_100g * factor, 2),
                carbs_g=round(ing.food.carbs_per_100g * factor, 2),
            )
        )

    return RecipeResponse(
        id=recipe.id,
        name=recipe.name,
        description=recipe.description,
        total_weight_g=recipe.total_weight_g,
        servings_count=recipe.servings_count,
        kcal_per_100g=recipe.kcal_per_100g,
        protein_per_100g=recipe.protein_per_100g,
        fat_per_100g=recipe.fat_per_100g,
        carbs_per_100g=recipe.carbs_per_100g,
        created_by_user_id=recipe.created_by_user_id,
        is_shared=recipe.is_shared,
        created_at=recipe.created_at,
        updated_at=recipe.updated_at,
        ingredients=ingredients_detail,
    )


async def _get_accessible_recipe(
    db: AsyncSession,
    recipe_id: UUID,
    user: User,
) -> Recipe:
    result = await db.execute(
        select(Recipe)
        .options(
            selectinload(Recipe.ingredients).selectinload(RecipeIngredient.food)
        )
        .where(Recipe.id == recipe_id)
    )
    recipe = result.scalar_one_or_none()
    if recipe is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Recette introuvable",
        )
    if recipe.created_by_user_id != user.id and not recipe.is_shared:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé à cette recette privée",
        )
    return recipe


@router.post("", response_model=RecipeResponse, status_code=status.HTTP_201_CREATED)
async def create_recipe(
    payload: RecipeCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RecipeResponse:
    """Create a recipe and compute its per-100g macros from its ingredients."""
    foods_map = await _load_foods_map(
        db, [item.food_id for item in payload.ingredients]
    )
    total_weight_g, kcal_100, protein_100, fat_100, carbs_100 = (
        _compute_recipe_nutrition(
            payload.ingredients, foods_map, payload.final_weight_g
        )
    )

    recipe = Recipe(
        name=payload.name.strip(),
        description=payload.description.strip() if payload.description else None,
        total_weight_g=total_weight_g,
        servings_count=payload.servings_count,
        kcal_per_100g=kcal_100,
        protein_per_100g=protein_100,
        fat_per_100g=fat_100,
        carbs_per_100g=carbs_100,
        created_by_user_id=current_user.id,
        is_shared=payload.is_shared,
        ingredients=[
            RecipeIngredient(food_id=item.food_id, quantity_g=item.quantity_g)
            for item in payload.ingredients
        ],
    )
    db.add(recipe)
    await db.commit()

    created = await _get_accessible_recipe(db, recipe.id, current_user)
    return _serialize_recipe(created)


@router.get("", response_model=list[RecipeSummary])
async def list_recipes(
    q: str = Query(default="", description="Optional search filter on recipe name"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Recipe]:
    """List personal and shared recipes."""
    stmt = select(Recipe).where(
        or_(
            Recipe.created_by_user_id == current_user.id,
            Recipe.is_shared.is_(True),
        )
    )
    if q.strip():
        stmt = stmt.where(Recipe.name.ilike(f"%{q.strip()}%"))
    stmt = stmt.order_by(Recipe.name.asc())
    result = await db.execute(stmt)
    return list(result.scalars().all())


@router.get("/{recipe_id}", response_model=RecipeResponse)
async def get_recipe(
    recipe_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RecipeResponse:
    """Get full recipe details with ingredient breakdown."""
    recipe = await _get_accessible_recipe(db, recipe_id, current_user)
    return _serialize_recipe(recipe)


@router.put("/{recipe_id}", response_model=RecipeResponse)
async def update_recipe(
    recipe_id: UUID,
    payload: RecipeUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RecipeResponse:
    """Update a recipe and recalculate its ingredients and per-100g macros."""
    recipe = await _get_accessible_recipe(db, recipe_id, current_user)

    if payload.name is not None:
        recipe.name = payload.name.strip()
    if payload.description is not None:
        recipe.description = payload.description.strip() or None
    if payload.servings_count is not None:
        recipe.servings_count = payload.servings_count
    if payload.is_shared is not None:
        recipe.is_shared = payload.is_shared

    if payload.ingredients is not None:
        ingredients_input = payload.ingredients
        foods_map = await _load_foods_map(
            db, [item.food_id for item in ingredients_input]
        )
        recipe.ingredients = [
            RecipeIngredient(food_id=item.food_id, quantity_g=item.quantity_g)
            for item in ingredients_input
        ]
        target_weight = payload.final_weight_g
    else:
        ingredients_input = [
            RecipeIngredientInput(food_id=ing.food_id, quantity_g=ing.quantity_g)
            for ing in recipe.ingredients
        ]
        foods_map = {ing.food_id: ing.food for ing in recipe.ingredients}
        target_weight = (
            payload.final_weight_g
            if payload.final_weight_g is not None
            else recipe.total_weight_g
        )

    total_weight_g, kcal_100, protein_100, fat_100, carbs_100 = (
        _compute_recipe_nutrition(ingredients_input, foods_map, target_weight)
    )
    recipe.total_weight_g = total_weight_g
    recipe.kcal_per_100g = kcal_100
    recipe.protein_per_100g = protein_100
    recipe.fat_per_100g = fat_100
    recipe.carbs_per_100g = carbs_100

    await db.commit()
    updated = await _get_accessible_recipe(db, recipe.id, current_user)
    return _serialize_recipe(updated)


@router.delete("/{recipe_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_recipe(
    recipe_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Delete a recipe if owned by user or shared."""
    recipe = await _get_accessible_recipe(db, recipe_id, current_user)
    await db.delete(recipe)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
