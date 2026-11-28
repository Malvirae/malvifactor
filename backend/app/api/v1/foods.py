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
from app.services.openfoodfacts import (
    get_or_fetch_food_by_barcode,
    normalize_search_text,
    search_openfoodfacts_products,
    tokenize_search_query,
)

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


def _recipe_portion_fields(recipe: Recipe) -> dict[str, float | None]:
    servings = float(recipe.servings_count) if recipe.servings_count else 0.0
    total_weight = float(recipe.total_weight_g)
    if servings <= 0 or total_weight <= 0:
        return {
            "servings": servings if servings > 0 else None,
            "total_weight_g": total_weight if total_weight > 0 else None,
            "serving_weight_g": None,
            "kcal_per_serving": None,
            "protein_per_serving": None,
            "fat_per_serving": None,
            "carbs_per_serving": None,
        }
    serving_weight = round(total_weight / servings, 1)
    factor = serving_weight / 100.0
    return {
        "servings": servings,
        "total_weight_g": total_weight,
        "serving_weight_g": serving_weight,
        "kcal_per_serving": round(recipe.kcal_per_100g * factor, 1),
        "protein_per_serving": round(recipe.protein_per_100g * factor, 1),
        "fat_per_serving": round(recipe.fat_per_100g * factor, 1),
        "carbs_per_serving": round(recipe.carbs_per_100g * factor, 1),
    }


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
    limit_picks: int = Query(default=5, ge=1, le=5),
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
            FoodLog.logged_date <= today + timedelta(days=1),
            or_(
                FoodLog.food_id.is_not(None),
                FoodLog.recipe_id.is_not(None),
                FoodLog.custom_name.is_not(None),
            ),
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

    global_last_qty: dict[tuple[str, UUID | str], float] = {}
    global_last_dt: dict[tuple[str, UUID | str], datetime] = {}
    global_quick_log: dict[str, FoodLog] = {}
    recent_keys: list[tuple[str, UUID | str]] = []

    window_scores: dict[tuple[str, UUID | str], float] = {}
    window_counts: dict[tuple[str, UUID | str], int] = {}
    window_last_qty: dict[tuple[str, UUID | str], float] = {}
    window_last_dt: dict[tuple[str, UUID | str], datetime] = {}
    window_quick_log: dict[str, FoodLog] = {}

    for log in logs:
        key: tuple[str, UUID | str]
        if log.food_id is not None:
            key = ("food", log.food_id)
        elif log.recipe_id is not None:
            key = ("recipe", log.recipe_id)
        elif log.custom_name and log.custom_name.strip():
            norm_quick = normalize_search_text(log.custom_name)
            if not norm_quick:
                continue
            key = ("quick", norm_quick)
        else:
            continue

        log_dt = datetime.combine(
            log.logged_date, log.logged_time, tzinfo=log.created_at.tzinfo
        )

        if key not in global_last_qty:
            global_last_qty[key] = float(log.quantity_g) if log.quantity_g > 0 else 1.0
            global_last_dt[key] = log_dt
            if key[0] == "quick":
                global_quick_log[str(key[1])] = log
            if len(recent_keys) < limit_recent * 2:
                recent_keys.append(key)

        if log.logged_date >= min_window_date:
            if _circular_minutes_diff(log.logged_time, resolved_hour) <= 90:
                days_since = max(0, (today - log.logged_date).days)
                weight = 1.0 / (1.0 + days_since / 21.0)
                window_scores[key] = window_scores.get(key, 0.0) + weight
                window_counts[key] = window_counts.get(key, 0) + 1
                if key not in window_last_qty:
                    window_last_qty[key] = float(log.quantity_g) if log.quantity_g > 0 else 1.0
                    window_last_dt[key] = log_dt
                    if key[0] == "quick":
                        window_quick_log[str(key[1])] = log

    sorted_pick_keys = sorted(
        window_scores.keys(),
        key=lambda k: (window_scores[k], window_last_dt[k]),
        reverse=True,
    )

    candidate_keys = list(dict.fromkeys([*sorted_pick_keys[: limit_picks * 2], *recent_keys]))
    food_ids = [uid for kind, uid in candidate_keys if kind == "food" and isinstance(uid, UUID)]
    recipe_ids = [uid for kind, uid in candidate_keys if kind == "recipe" and isinstance(uid, UUID)]

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
        key: tuple[str, UUID | str],
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

        if kind == "quick":
            qlog = (
                window_quick_log.get(str(uid)) if for_window else None
            ) or global_quick_log.get(str(uid))
            if qlog is None or not qlog.custom_name:
                return None
            return FoodSuggestionItem(
                id=qlog.id,
                item_type="quick_add",
                source="quick_add",
                name=qlog.custom_name.strip(),
                brand=None,
                stores=None,
                serving_size_g=round(qty, 1),
                serving_label="Ajout libre",
                kcal_per_100g=round(qlog.kcal, 1),
                protein_per_100g=round(qlog.protein_g, 1),
                fat_per_100g=round(qlog.fat_g, 1),
                carbs_per_100g=round(qlog.carbs_g, 1),
                fiber_per_100g=0.0,
                last_quantity_g=round(qty, 1),
                last_serving_label="Ajout libre",
                preview_kcal=round(qlog.kcal, 1),
                preview_protein_g=round(qlog.protein_g, 1),
                preview_fat_g=round(qlog.fat_g, 1),
                preview_carbs_g=round(qlog.carbs_g, 1),
                last_logged_at=last_dt,
                times_logged_at_hour=window_counts.get(key, 0) if for_window else 0,
            )

        factor = qty / 100.0
        if kind == "food" and isinstance(uid, UUID):
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
                stores=food.stores,
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

        if not isinstance(uid, UUID):
            return None
        recipe = recipes_map.get(uid)
        if recipe is None:
            return None
        portion_fields = _recipe_portion_fields(recipe)
        serving_weight = portion_fields["serving_weight_g"] or 100.0
        return FoodSuggestionItem(
            id=recipe.id,
            item_type="recipe",
            source="recipe",
            name=recipe.name,
            brand=None,
            serving_size_g=serving_weight,
            serving_label="1 portion" if portion_fields["serving_weight_g"] else None,
            kcal_per_100g=recipe.kcal_per_100g,
            protein_per_100g=recipe.protein_per_100g,
            fat_per_100g=recipe.fat_per_100g,
            carbs_per_100g=recipe.carbs_per_100g,
            fiber_per_100g=0.0,
            last_quantity_g=round(qty, 1),
            last_serving_label=_format_serving_label(
                qty,
                serving_weight,
                f"1 portion ({serving_weight:.1f} g)"
                if portion_fields["serving_weight_g"]
                else None,
            ),
            preview_kcal=round(recipe.kcal_per_100g * factor, 1),
            preview_protein_g=round(recipe.protein_per_100g * factor, 1),
            preview_fat_g=round(recipe.fat_per_100g * factor, 1),
            preview_carbs_g=round(recipe.carbs_per_100g * factor, 1),
            last_logged_at=last_dt,
            times_logged_at_hour=window_counts.get(key, 0) if for_window else 0,
            **portion_fields,
        )

    max_picks = min(limit_picks, 5)
    time_picks: list[FoodSuggestionItem] = []
    for k in sorted_pick_keys:
        if len(time_picks) >= max_picks:
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
    q: str = Query(default="", description="Search query (food name, brand, or store)"),
    limit: int = Query(default=30, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FoodResponse]:
    """Search Ciqual, custom foods, recipes, and OpenFoodFacts using multi-token accent-insensitive matching."""
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

    tokens = tokenize_search_query(query_text)
    if not tokens:
        return []

    # 1. Local Food search (Ciqual, custom, cached OFF) across name, brand, stores
    token_filters = [
        or_(
            func.unaccent(Food.name).ilike(f"%{token}%"),
            func.unaccent(func.coalesce(Food.brand, "")).ilike(f"%{token}%"),
            func.unaccent(func.coalesce(Food.stores, "")).ilike(f"%{token}%"),
        )
        for token in tokens
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
    local_stmt = (
        select(Food)
        .where(visibility, and_(*token_filters))
        .order_by(
            custom_priority.asc(),
            func.similarity(Food.name, query_text).desc(),
            Food.name.asc(),
        )
        .limit(45)
    )
    local_res = await db.execute(local_stmt)
    local_foods = list(local_res.scalars().all())

    # 2. Local accessible Recipes search
    recipe_filters = [
        or_(
            func.unaccent(Recipe.name).ilike(f"%{token}%"),
            func.unaccent(func.coalesce(Recipe.description, "")).ilike(f"%{token}%"),
        )
        for token in tokens
    ]
    recipe_stmt = (
        select(Recipe)
        .where(
            or_(
                Recipe.created_by_user_id == current_user.id,
                Recipe.is_shared.is_(True),
            ),
            and_(*recipe_filters),
        )
        .order_by(Recipe.name.asc())
        .limit(15)
    )
    recipe_res = await db.execute(recipe_stmt)
    matched_recipes = list(recipe_res.scalars().all())

    # 3. Live French OpenFoodFacts search + DB cache upsert
    off_foods = await search_openfoodfacts_products(
        db,
        query=query_text,
        tokens=tokens,
        limit=25,
    )

    # 4. Merge deduplicating foods by id and (source, external_id)
    merged_foods: list[Food] = []
    seen_food_ids: set[UUID] = set()
    seen_external: set[tuple[str, str]] = set()
    for food in [*local_foods, *off_foods]:
        if food.id in seen_food_ids:
            continue
        ext_key = (food.source.value, food.external_id) if food.external_id else None
        if ext_key is not None and ext_key in seen_external:
            continue
        seen_food_ids.add(food.id)
        if ext_key is not None:
            seen_external.add(ext_key)
        merged_foods.append(food)

    # 5. Fetch personal log frequency & last_quantity_g for foods and recipes
    food_ids = [f.id for f in merged_foods]
    recipe_ids = [r.id for r in matched_recipes]

    food_counts: dict[UUID, int] = {}
    food_last_qty: dict[UUID, float] = {}
    if food_ids:
        cnt_res = await db.execute(
            select(FoodLog.food_id, func.count(FoodLog.id))
            .where(FoodLog.user_id == current_user.id, FoodLog.food_id.in_(food_ids))
            .group_by(FoodLog.food_id)
        )
        food_counts = {row[0]: int(row[1]) for row in cnt_res.all() if row[0] is not None}

        qty_res = await db.execute(
            select(FoodLog.food_id, FoodLog.quantity_g)
            .distinct(FoodLog.food_id)
            .where(FoodLog.user_id == current_user.id, FoodLog.food_id.in_(food_ids))
            .order_by(
                FoodLog.food_id,
                FoodLog.logged_date.desc(),
                FoodLog.logged_time.desc(),
                FoodLog.created_at.desc(),
            )
        )
        food_last_qty = {
            row[0]: float(row[1])
            for row in qty_res.all()
            if row[0] is not None and row[1] is not None
        }

    recipe_counts: dict[UUID, int] = {}
    recipe_last_qty: dict[UUID, float] = {}
    if recipe_ids:
        rcnt_res = await db.execute(
            select(FoodLog.recipe_id, func.count(FoodLog.id))
            .where(FoodLog.user_id == current_user.id, FoodLog.recipe_id.in_(recipe_ids))
            .group_by(FoodLog.recipe_id)
        )
        recipe_counts = {row[0]: int(row[1]) for row in rcnt_res.all() if row[0] is not None}

        rqty_res = await db.execute(
            select(FoodLog.recipe_id, FoodLog.quantity_g)
            .distinct(FoodLog.recipe_id)
            .where(FoodLog.user_id == current_user.id, FoodLog.recipe_id.in_(recipe_ids))
            .order_by(
                FoodLog.recipe_id,
                FoodLog.logged_date.desc(),
                FoodLog.logged_time.desc(),
                FoodLog.created_at.desc(),
            )
        )
        recipe_last_qty = {
            row[0]: float(row[1])
            for row in rqty_res.all()
            if row[0] is not None and row[1] is not None
        }

    norm_query = normalize_search_text(query_text)
    scored_responses: list[tuple[float, str, FoodResponse]] = []

    for food in merged_foods:
        norm_name = normalize_search_text(food.name)
        norm_brand = normalize_search_text(food.brand)
        norm_stores = normalize_search_text(food.stores)
        combined = f"{norm_name} {norm_brand} {norm_stores}".strip()

        score = 0.0
        if norm_name == norm_query:
            score += 120.0
        elif norm_name.startswith(norm_query):
            score += 70.0
        elif norm_query in norm_name:
            score += 35.0

        matched_tokens = sum(1 for t in tokens if t in combined)
        score += matched_tokens * 18.0
        if matched_tokens == len(tokens):
            score += 45.0

        name_matches = sum(1 for t in tokens if t in norm_name)
        score += name_matches * 8.0

        if food.source == FoodSource.CUSTOM and food.created_by_user_id == current_user.id:
            score += 22.0
        elif food.source == FoodSource.CIQUAL and name_matches == len(tokens):
            score += 14.0

        usage = food_counts.get(food.id, 0)
        if usage > 0:
            score += min(30.0, usage * 5.0)

        resp = FoodResponse.model_validate(food).model_copy(
            update={"last_quantity_g": food_last_qty.get(food.id)}
        )
        scored_responses.append((score, norm_name, resp))

    for recipe in matched_recipes:
        norm_name = normalize_search_text(recipe.name)
        norm_desc = normalize_search_text(recipe.description)
        combined = f"{norm_name} {norm_desc}".strip()

        score = 20.0
        if norm_name == norm_query:
            score += 120.0
        elif norm_name.startswith(norm_query):
            score += 70.0
        elif norm_query in norm_name:
            score += 35.0

        matched_tokens = sum(1 for t in tokens if t in combined)
        score += matched_tokens * 18.0
        if matched_tokens == len(tokens):
            score += 45.0

        usage = recipe_counts.get(recipe.id, 0)
        if usage > 0:
            score += min(30.0, usage * 5.0)

        portion_fields = _recipe_portion_fields(recipe)
        default_serving = portion_fields["serving_weight_g"] or 100.0
        resp = FoodResponse(
            id=recipe.id,
            source="recipe",
            external_id=None,
            name=recipe.name,
            brand=None,
            stores=None,
            serving_size_g=default_serving,
            serving_label="1 portion" if portion_fields["serving_weight_g"] else None,
            kcal_per_100g=recipe.kcal_per_100g,
            protein_per_100g=recipe.protein_per_100g,
            fat_per_100g=recipe.fat_per_100g,
            carbs_per_100g=recipe.carbs_per_100g,
            fiber_per_100g=0.0,
            created_by_user_id=recipe.created_by_user_id,
            created_at=recipe.created_at,
            last_quantity_g=recipe_last_qty.get(recipe.id),
            **portion_fields,
        )
        scored_responses.append((score, norm_name, resp))

    scored_responses.sort(key=lambda item: (-item[0], len(item[1]), item[1]))
    return [item[2] for item in scored_responses[:limit]]


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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Lookup food by EAN barcode prioritizing the user's custom food over OFF."""
    return await get_or_fetch_food_by_barcode(db, barcode, user_id=current_user.id)


@router.post("", response_model=FoodResponse, status_code=status.HTTP_201_CREATED)
async def create_custom_food(
    payload: FoodCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Food:
    """Create or upsert (by barcode) a custom food owned by the current user."""
    clean_ext = payload.external_id.strip().replace(" ", "") if payload.external_id else None
    if clean_ext:
        existing_res = await db.execute(
            select(Food)
            .where(
                Food.source == FoodSource.CUSTOM,
                Food.created_by_user_id == current_user.id,
                Food.external_id == clean_ext,
            )
            .limit(1)
        )
        existing = existing_res.scalar_one_or_none()
        if existing is not None:
            existing.name = payload.name.strip()
            existing.brand = payload.brand.strip() if payload.brand else None
            existing.stores = payload.stores.strip() if payload.stores else None
            existing.serving_size_g = payload.serving_size_g
            existing.serving_label = (
                payload.serving_label.strip() if payload.serving_label else None
            )
            existing.kcal_per_100g = payload.kcal_per_100g
            existing.protein_per_100g = payload.protein_per_100g
            existing.fat_per_100g = payload.fat_per_100g
            existing.carbs_per_100g = payload.carbs_per_100g
            existing.fiber_per_100g = payload.fiber_per_100g
            await db.commit()
            await db.refresh(existing)
            return existing

    food = Food(
        source=FoodSource.CUSTOM,
        external_id=clean_ext,
        name=payload.name.strip(),
        brand=payload.brand.strip() if payload.brand else None,
        stores=payload.stores.strip() if payload.stores else None,
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

    if food.source == FoodSource.CUSTOM and food.created_by_user_id == current_user.id:
        updates = payload.model_dump(exclude_unset=True)
        for field, value in updates.items():
            if isinstance(value, str):
                value = value.strip() or None
            setattr(food, field, value)
        await db.commit()
        await db.refresh(food)
        return food

    clean_ext = food.external_id.strip().replace(" ", "") if food.external_id else None
    if clean_ext:
        existing_res = await db.execute(
            select(Food)
            .where(
                Food.source == FoodSource.CUSTOM,
                Food.created_by_user_id == current_user.id,
                Food.external_id == clean_ext,
            )
            .limit(1)
        )
        existing_custom = existing_res.scalar_one_or_none()
        if existing_custom is not None:
            existing_custom.name = payload.name.strip() if payload.name else food.name
            if payload.brand is not None:
                existing_custom.brand = payload.brand.strip() or None
            if payload.stores is not None:
                existing_custom.stores = payload.stores.strip() or None
            if payload.serving_size_g is not None:
                existing_custom.serving_size_g = payload.serving_size_g
            if payload.serving_label is not None:
                existing_custom.serving_label = payload.serving_label.strip() or None
            if payload.kcal_per_100g is not None:
                existing_custom.kcal_per_100g = payload.kcal_per_100g
            if payload.protein_per_100g is not None:
                existing_custom.protein_per_100g = payload.protein_per_100g
            if payload.fat_per_100g is not None:
                existing_custom.fat_per_100g = payload.fat_per_100g
            if payload.carbs_per_100g is not None:
                existing_custom.carbs_per_100g = payload.carbs_per_100g
            if payload.fiber_per_100g is not None:
                existing_custom.fiber_per_100g = payload.fiber_per_100g
            await db.commit()
            await db.refresh(existing_custom)
            return existing_custom

    customized = Food(
        source=FoodSource.CUSTOM,
        external_id=clean_ext,
        name=payload.name.strip() if payload.name else food.name,
        brand=(
            payload.brand.strip() or None
            if payload.brand is not None
            else food.brand
        ),
        stores=(
            payload.stores.strip() or None
            if payload.stores is not None
            else food.stores
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
