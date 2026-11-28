from datetime import date, datetime, time, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.food import Food, FoodSource, Recipe
from app.models.tracking import FoodLog
from app.models.user import User
from app.schemas.food import (
    FoodCreate,
    FoodCustomizeRequest,
    FoodResponse,
    FoodSuggestionItem,
    FoodSuggestionsResponse,
    FoodUpdate,
)
from app.services.openfoodfacts import get_or_fetch_food_by_barcode

router = APIRouter(prefix="/foods", tags=["foods"])


def _visibility_filter(user_id: UUID):
    return or_(
        Food.created_by_user_id.is_(None),
        Food.created_by_user_id == user_id,
    )


def _circular_minutes_diff(log_time: time, target_hour: int) -> int:
    log_mins = log_time.hour * 60 + log_time.minute
    target_mins = target_hour * 60
    diff = abs(log_mins - target_mins)
    return min(diff, 1440 - diff)


def _format_serving_label(quantity_g: float, base_size_g: float, base_label: str | None) -> str:
    if base_label and abs(quantity_g - base_size_g) < 0.05:
        return base_label
    qty_str = f"{round(quantity_g)}" if abs(quantity_g - round(quantity_g)) < 0.05 else f"{quantity_g:.1f}"
    return f"{qty_str} g"


async def _attach_last_quantities(
    db: AsyncSession,
    user_id: UUID,
    foods: list[Food],
) -> list[FoodResponse]:
    if not foods:
        return []
    food_ids = [f.id for f in foods]
    latest_stmt = (
        select(FoodLog.food_id, FoodLog.quantity_g)
        .distinct(FoodLog.food_id)
        .where(
            FoodLog.user_id == user_id,
            FoodLog.food_id.in_(food_ids),
        )
        .order_by(
            FoodLog.food_id,
            FoodLog.logged_date.desc(),
            FoodLog.logged_time.desc(),
            FoodLog.created_at.desc(),
        )
    )
    res = await db.execute(latest_stmt)
    last_qty_by_id = {
        row[0]: float(row[1])
        for row in res.all()
        if row[0] is not None and row[1] is not None
    }
    return [
        FoodResponse.model_validate(f).model_copy(
            update={"last_quantity_g": last_qty_by_id.get(f.id)}
        )
        for f in foods
    ]


@router.get("/suggestions", response_model=FoodSuggestionsResponse)
async def get_food_suggestions(
    target_hour: int | None = Query(default=None, ge=0, le=23),
    limit_picks: int = Query(default=8, ge=1, le=30),
    limit_recent: int = Query(default=30, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FoodSuggestionsResponse:
    """Return habitual time-window picks (±90 min over 90d) and recent foods/recipes."""
    resolved_hour = target_hour if target_hour is not None else datetime.now().hour
    today = date.today()
    min_window_date = today - timedelta(days=90)

    logs_res = await db.execute(
        select(FoodLog)
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date <= today,
            or_(FoodLog.food_id.is_not(None), FoodLog.recipe_id.is_not(None)),
        )
        .order_by(
            FoodLog.logged_date.desc(),
            FoodLog.logged_time.desc(),
            FoodLog.created_at.desc(),
        )
        .limit(2500)
    )
    logs = list(logs_res.scalars().all())

    if not logs:
        return FoodSuggestionsResponse(
            target_hour=resolved_hour,
            time_picks=[],
            recent_foods=[],
        )

    global_last_qty: dict[tuple[str, UUID], float] = {}
    global_last_dt: dict[tuple[str, UUID], datetime] = {}
    recent_keys: list[tuple[str, UUID]] = []

    window_scores: dict[tuple[str, UUID], float] = {}
    window_counts: dict[tuple[str, UUID], int] = {}
    window_last_qty: dict[tuple[str, UUID], float] = {}
    window_last_dt: dict[tuple[str, UUID], datetime] = {}

    for log in logs:
        if log.food_id is not None:
            key = ("food", log.food_id)
        elif log.recipe_id is not None:
            key = ("recipe", log.recipe_id)
        else:
            continue

        log_dt = datetime.combine(
            log.logged_date, log.logged_time, tzinfo=log.created_at.tzinfo
        )

        if key not in global_last_qty:
            global_last_qty[key] = float(log.quantity_g)
            global_last_dt[key] = log_dt
            if len(recent_keys) < limit_recent * 2:
                recent_keys.append(key)

        if log.logged_date >= min_window_date:
            if _circular_minutes_diff(log.logged_time, resolved_hour) <= 90:
                days_since = max(0, (today - log.logged_date).days)
                weight = 1.0 / (1.0 + days_since / 21.0)
                window_scores[key] = window_scores.get(key, 0.0) + weight
                window_counts[key] = window_counts.get(key, 0) + 1
                if key not in window_last_qty:
                    window_last_qty[key] = float(log.quantity_g)
                    window_last_dt[key] = log_dt

    sorted_pick_keys = sorted(
        window_scores.keys(),
        key=lambda k: (window_scores[k], window_last_dt[k]),
        reverse=True,
    )

    candidate_keys = list(dict.fromkeys([*sorted_pick_keys[: limit_picks * 2], *recent_keys]))
    food_ids = [uid for kind, uid in candidate_keys if kind == "food"]
    recipe_ids = [uid for kind, uid in candidate_keys if kind == "recipe"]

    foods_map: dict[UUID, Food] = {}
    if food_ids:
        f_res = await db.execute(
            select(Food).where(Food.id.in_(food_ids), _visibility_filter(current_user.id))
        )
        foods_map = {f.id: f for f in f_res.scalars().all()}

    recipes_map: dict[UUID, Recipe] = {}
    if recipe_ids:
        r_res = await db.execute(
            select(Recipe).where(
                Recipe.id.in_(recipe_ids),
                or_(
                    Recipe.created_by_user_id == current_user.id,
                    Recipe.is_shared.is_(True),
                ),
            )
        )
        recipes_map = {r.id: r for r in r_res.scalars().all()}

    def _build_item(
        key: tuple[str, UUID],
        *,
        for_window: bool,
    ) -> FoodSuggestionItem | None:
        kind, uid = key
        qty = (
            window_last_qty.get(key) if for_window else None
        ) or global_last_qty.get(key)
        last_dt = (
            window_last_dt.get(key) if for_window else None
        ) or global_last_dt.get(key)
        if qty is None or qty <= 0 or last_dt is None:
            return None

        factor = qty / 100.0
        if kind == "food":
            food = foods_map.get(uid)
            if food is None:
                return None
            item_type = "custom" if food.source == FoodSource.CUSTOM else "standard"
            return FoodSuggestionItem(
                id=food.id,
                item_type=item_type,
                source=food.source.value,
                name=food.name,
                brand=food.brand,
                serving_size_g=food.serving_size_g,
                serving_label=food.serving_label,
                kcal_per_100g=food.kcal_per_100g,
                protein_per_100g=food.protein_per_100g,
                fat_per_100g=food.fat_per_100g,
                carbs_per_100g=food.carbs_per_100g,
                fiber_per_100g=food.fiber_per_100g,
                last_quantity_g=round(qty, 1),
                last_serving_label=_format_serving_label(
                    qty, food.serving_size_g, food.serving_label
                ),
                preview_kcal=round(food.kcal_per_100g * factor, 1),
                preview_protein_g=round(food.protein_per_100g * factor, 1),
                preview_fat_g=round(food.fat_per_100g * factor, 1),
                preview_carbs_g=round(food.carbs_per_100g * factor, 1),
                last_logged_at=last_dt,
                times_logged_at_hour=window_counts.get(key, 0) if for_window else 0,
            )

        recipe = recipes_map.get(uid)
        if recipe is None:
            return None
        return FoodSuggestionItem(
            id=recipe.id,
            item_type="recipe",
            source="recipe",
            name=recipe.name,
            brand=None,
            serving_size_g=round(recipe.total_weight_g / max(recipe.servings_count, 1.0), 1),
            serving_label="1 portion",
            kcal_per_100g=recipe.kcal_per_100g,
            protein_per_100g=recipe.protein_per_100g,
            fat_per_100g=recipe.fat_per_100g,
            carbs_per_100g=recipe.carbs_per_100g,
            fiber_per_100g=0.0,
            last_quantity_g=round(qty, 1),
            last_serving_label=_format_serving_label(qty, 100.0, None),
            preview_kcal=round(recipe.kcal_per_100g * factor, 1),
            preview_protein_g=round(recipe.protein_per_100g * factor, 1),
            preview_fat_g=round(recipe.fat_per_100g * factor, 1),
            preview_carbs_g=round(recipe.carbs_per_100g * factor, 1),
            last_logged_at=last_dt,
            times_logged_at_hour=window_counts.get(key, 0) if for_window else 0,
        )

    time_picks: list[FoodSuggestionItem] = []
    for k in sorted_pick_keys:
        if len(time_picks) >= limit_picks:
            break
        built = _build_item(k, for_window=True)
        if built is not None:
            time_picks.append(built)

    recent_foods: list[FoodSuggestionItem] = []
    for k in recent_keys:
        if len(recent_foods) >= limit_recent:
            break
        built = _build_item(k, for_window=False)
        if built is not None:
            recent_foods.append(built)

    return FoodSuggestionsResponse(
        target_hour=resolved_hour,
        time_picks=time_picks,
        recent_foods=recent_foods,
    )


@router.get("/search", response_model=list[FoodResponse])
async def search_foods(
    q: str = Query(default="", description="Search query (food name or brand)"),
    limit: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FoodResponse]:
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
        return await _attach_last_quantities(db, current_user.id, foods)

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
    return await _attach_last_quantities(
        db, current_user.id, list(result.scalars().all())
    )


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
