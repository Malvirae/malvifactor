from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.food import Food, FoodSource
from app.models.tracking import FoodLog
from app.models.user import User
from app.schemas.food import (
    FoodCreate,
    FoodCustomizeRequest,
    FoodResponse,
    FoodUpdate,
)
from app.services.openfoodfacts import get_or_fetch_food_by_barcode

router = APIRouter(prefix="/foods", tags=["foods"])


def _visibility_filter(user_id: UUID):
    return or_(
        Food.created_by_user_id.is_(None),
        Food.created_by_user_id == user_id,
    )


@router.get("/search", response_model=list[FoodResponse])
async def search_foods(
    q: str = Query(default="", description="Search query (food name or brand)"),
    limit: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Food]:
    """Search foods using multi-term ILIKE + pg_trgm similarity, or return recent foods."""
    query_text = q.strip()
    visibility = _visibility_filter(current_user.id)

    if not query_text:
        recent_ids_result = await db.execute(
            select(FoodLog.food_id)
            .where(
                FoodLog.user_id == current_user.id,
                FoodLog.food_id.is_not(None),
            )
            .group_by(FoodLog.food_id)
            .order_by(func.max(FoodLog.created_at).desc())
            .limit(limit)
        )
        recent_ids = [row[0] for row in recent_ids_result.all() if row[0] is not None]

        foods: list[Food] = []
        if recent_ids:
            recent_foods_res = await db.execute(
                select(Food).where(Food.id.in_(recent_ids), visibility)
            )
            by_id = {f.id: f for f in recent_foods_res.scalars().all()}
            foods = [by_id[fid] for fid in recent_ids if fid in by_id]

        remaining = limit - len(foods)
        if remaining > 0:
            fallback_stmt = select(Food).where(visibility)
            if foods:
                fallback_stmt = fallback_stmt.where(
                    Food.id.notin_([f.id for f in foods])
                )
            fallback_stmt = fallback_stmt.order_by(Food.name.asc()).limit(remaining)
            fallback_res = await db.execute(fallback_stmt)
            foods.extend(fallback_res.scalars().all())
        return foods

    terms = [term for term in query_text.split() if term]
    term_filters = [
        or_(Food.name.ilike(f"%{term}%"), Food.brand.ilike(f"%{term}%"))
        for term in terms
    ]

    custom_priority = case(
        (
            and_(
                Food.source == FoodSource.CUSTOM,
                Food.created_by_user_id == current_user.id,
            ),
            0,
        ),
        else_=1,
    )

    stmt = (
        select(Food)
        .where(visibility, and_(*term_filters))
        .order_by(
            custom_priority.asc(),
            func.similarity(Food.name, query_text).desc(),
            Food.name.asc(),
        )
        .limit(limit)
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


@router.get("/custom", response_model=list[FoodResponse])
async def list_custom_foods(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Food]:
    """List all custom foods created by the current user, sorted by name."""
    stmt = (
        select(Food)
        .where(
            Food.source == FoodSource.CUSTOM,
            Food.created_by_user_id == current_user.id,
        )
        .order_by(Food.name.asc())
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


@router.get("/barcode/{barcode}", response_model=FoodResponse)
async def get_food_by_barcode(
    barcode: str,
    _: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Lookup food by EAN barcode via local cache or Open Food Facts."""
    return await get_or_fetch_food_by_barcode(db, barcode)


@router.post("", response_model=FoodResponse, status_code=status.HTTP_201_CREATED)
async def create_custom_food(
    payload: FoodCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Create a custom food owned by the current user."""
    food = Food(
        source=FoodSource.CUSTOM,
        external_id=payload.external_id.strip() if payload.external_id else None,
        name=payload.name.strip(),
        brand=payload.brand.strip() if payload.brand else None,
        serving_size_g=payload.serving_size_g,
        serving_label=payload.serving_label.strip() if payload.serving_label else None,
        kcal_per_100g=payload.kcal_per_100g,
        protein_per_100g=payload.protein_per_100g,
        fat_per_100g=payload.fat_per_100g,
        carbs_per_100g=payload.carbs_per_100g,
        fiber_per_100g=payload.fiber_per_100g,
        created_by_user_id=current_user.id,
    )
    db.add(food)
    await db.commit()
    await db.refresh(food)
    return food


async def _get_owned_custom_food(
    db: AsyncSession,
    food_id: UUID,
    user: User,
) -> Food:
    result = await db.execute(select(Food).where(Food.id == food_id))
    food = result.scalar_one_or_none()
    if food is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aliment introuvable",
        )
    if food.source != FoodSource.CUSTOM or food.created_by_user_id != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Seuls vos aliments personnalisés peuvent être modifiés ou supprimés",
        )
    return food


@router.put("/{food_id}", response_model=FoodResponse)
async def update_custom_food(
    food_id: UUID,
    payload: FoodUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Update a custom food owned by the current user."""
    food = await _get_owned_custom_food(db, food_id, current_user)
    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        if isinstance(value, str):
            value = value.strip() or None
        setattr(food, field, value)

    await db.commit()
    await db.refresh(food)
    return food


@router.delete("/{food_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_custom_food(
    food_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Delete a custom food owned by the current user."""
    food = await _get_owned_custom_food(db, food_id, current_user)
    await db.delete(food)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{food_id}/customize", response_model=FoodResponse)
async def customize_food(
    food_id: UUID,
    payload: FoodCustomizeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Update a custom food or create a custom override preserving external_id."""
    result = await db.execute(select(Food).where(Food.id == food_id))
    food = result.scalar_one_or_none()
    if food is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aliment introuvable",
        )

    if food.source == FoodSource.CUSTOM:
        updates = payload.model_dump(exclude_unset=True)
        for field, value in updates.items():
            if isinstance(value, str):
                value = value.strip() or None
            setattr(food, field, value)
        await db.commit()
        await db.refresh(food)
        return food

    customized = Food(
        source=FoodSource.CUSTOM,
        external_id=food.external_id,
        name=payload.name.strip() if payload.name else food.name,
        brand=(
            payload.brand.strip() or None
            if payload.brand is not None
            else food.brand
        ),
        serving_size_g=(
            payload.serving_size_g
            if payload.serving_size_g is not None
            else food.serving_size_g
        ),
        serving_label=(
            payload.serving_label.strip() or None
            if payload.serving_label is not None
            else food.serving_label
        ),
        kcal_per_100g=(
            payload.kcal_per_100g
            if payload.kcal_per_100g is not None
            else food.kcal_per_100g
        ),
        protein_per_100g=(
            payload.protein_per_100g
            if payload.protein_per_100g is not None
            else food.protein_per_100g
        ),
        fat_per_100g=(
            payload.fat_per_100g
            if payload.fat_per_100g is not None
            else food.fat_per_100g
        ),
        carbs_per_100g=(
            payload.carbs_per_100g
            if payload.carbs_per_100g is not None
            else food.carbs_per_100g
        ),
        fiber_per_100g=(
            payload.fiber_per_100g
            if payload.fiber_per_100g is not None
            else food.fiber_per_100g
        ),
        created_by_user_id=current_user.id,
    )
    db.add(customized)
    await db.commit()
    await db.refresh(customized)
    return customized
