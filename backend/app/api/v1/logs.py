from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.profile import _get_or_create_profile
from app.core.database import get_db
from app.models.food import Food, FoodSource, Recipe
from app.models.tracking import FoodLog
from app.models.user import User
from app.services.tdee_engine import get_targets_for_date
from app.schemas.logs import (
    DayLogsResponse,
    DaySummaryItem,
    FoodLogBatchCreateRequest,
    FoodLogBatchCreateResponse,
    FoodLogBatchDeleteRequest,
    FoodLogBatchDeleteResponse,
    FoodLogCopyRequest,
    FoodLogCreate,
    FoodLogItem,
    FoodLogMoveRequest,
    FoodLogUpdate,
    MacroSummary,
)

router = APIRouter(prefix="/logs", tags=["logs"])


def _serialize_log_item(
    log: FoodLog,
    food: Food | None,
    recipe: Recipe | None,
) -> FoodLogItem:
    if food is not None:
        display_name = food.name
        brand = food.brand
        stores = food.stores
        source = "openfoodfacts" if food.source == FoodSource.OFF else food.source.value
        category = None
    elif recipe is not None:
        display_name = recipe.name
        brand = None
        stores = None
        source = "recipe"
        category = None
    else:
        display_name = log.custom_name or "Ajout rapide"
        brand = None
        stores = None
        source = "quick_add"
        category = None

    recipe_servings: float | None = None
    recipe_total_weight_g: float | None = None
    recipe_serving_weight_g: float | None = None
    if recipe is not None:
        recipe_servings = float(recipe.servings_count) if recipe.servings_count else None
        recipe_total_weight_g = float(recipe.total_weight_g)
        if recipe_servings and recipe_servings > 0:
            recipe_serving_weight_g = round(recipe.total_weight_g / recipe_servings, 1)

    return FoodLogItem(
        id=log.id,
        logged_date=log.logged_date,
        logged_time=log.logged_time,
        food_id=log.food_id,
        recipe_id=log.recipe_id,
        custom_name=log.custom_name,
        display_name=display_name,
        brand=brand,
        stores=stores,
        source=source,
        category=category,
        quantity_g=log.quantity_g,
        kcal=log.kcal,
        protein_g=log.protein_g,
        fat_g=log.fat_g,
        carbs_g=log.carbs_g,
        created_at=log.created_at,
        recipe_servings=recipe_servings,
        recipe_total_weight_g=recipe_total_weight_g,
        recipe_serving_weight_g=recipe_serving_weight_g,
    )


async def _load_enriched_logs(
    db: AsyncSession,
    logs: list[FoodLog],
) -> list[FoodLogItem]:
    food_ids = list({log.food_id for log in logs if log.food_id is not None})
    recipe_ids = list({log.recipe_id for log in logs if log.recipe_id is not None})

    foods_map: dict[UUID, Food] = {}
    if food_ids:
        res = await db.execute(select(Food).where(Food.id.in_(food_ids)))
        foods_map = {f.id: f for f in res.scalars().all()}

    recipes_map: dict[UUID, Recipe] = {}
    if recipe_ids:
        res = await db.execute(select(Recipe).where(Recipe.id.in_(recipe_ids)))
        recipes_map = {r.id: r for r in res.scalars().all()}

    return [
        _serialize_log_item(
            log,
            foods_map.get(log.food_id) if log.food_id else None,
            recipes_map.get(log.recipe_id) if log.recipe_id else None,
        )
        for log in logs
    ]


@router.get("/day/{target_date}", response_model=DayLogsResponse)
async def get_day_logs(
    target_date: date,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DayLogsResponse:
    """Return chronological food timeline and macro totals/targets/remaining for a day."""
    stmt = (
        select(FoodLog)
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date == target_date,
        )
        .order_by(FoodLog.logged_time.asc(), FoodLog.created_at.asc())
    )
    result = await db.execute(stmt)
    logs = list(result.scalars().all())
    entries = await _load_enriched_logs(db, logs)

    total_kcal = round(sum(e.kcal for e in entries), 1)
    total_protein = round(sum(e.protein_g for e in entries), 1)
    total_fat = round(sum(e.fat_g for e in entries), 1)
    total_carbs = round(sum(e.carbs_g for e in entries), 1)

    profile = await _get_or_create_profile(db, current_user)
    date_targets = await get_targets_for_date(
        db, current_user.id, target_date, profile
    )
    totals = MacroSummary(
        kcal=total_kcal,
        protein_g=total_protein,
        fat_g=total_fat,
        carbs_g=total_carbs,
    )
    targets = MacroSummary(
        kcal=round(date_targets.calorie_target, 1),
        protein_g=round(date_targets.protein_g, 1),
        fat_g=round(date_targets.fat_g, 1),
        carbs_g=round(date_targets.carbs_g, 1),
    )
    remaining = MacroSummary(
        kcal=round(targets.kcal - totals.kcal, 1),
        protein_g=round(targets.protein_g - totals.protein_g, 1),
        fat_g=round(targets.fat_g - totals.fat_g, 1),
        carbs_g=round(targets.carbs_g - totals.carbs_g, 1),
    )
    return DayLogsResponse(
        date=target_date,
        entries=entries,
        totals=totals,
        targets=targets,
        remaining=remaining,
    )


@router.post("", response_model=FoodLogItem, status_code=status.HTTP_201_CREATED)
async def create_food_log(
    payload: FoodLogCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FoodLogItem:
    """Log food intake from a food item, recipe, or free quick-add."""
    food: Food | None = None
    recipe: Recipe | None = None

    if payload.food_id is not None:
        res = await db.execute(select(Food).where(Food.id == payload.food_id))
        food = res.scalar_one_or_none()
        if food is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Aliment introuvable",
            )
        if (
            food.created_by_user_id is not None
            and food.created_by_user_id != current_user.id
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Accès refusé à cet aliment privé",
            )
        qty = payload.quantity_g or 100.0
        factor = qty / 100.0
        kcal = round(food.kcal_per_100g * factor, 2)
        protein_g = round(food.protein_per_100g * factor, 2)
        fat_g = round(food.fat_per_100g * factor, 2)
        carbs_g = round(food.carbs_per_100g * factor, 2)
    elif payload.recipe_id is not None:
        res = await db.execute(select(Recipe).where(Recipe.id == payload.recipe_id))
        recipe = res.scalar_one_or_none()
        if recipe is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Recette introuvable",
            )
        if recipe.created_by_user_id != current_user.id and not recipe.is_shared:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Accès refusé à cette recette privée",
            )
        qty = payload.quantity_g or 100.0
        factor = qty / 100.0
        kcal = round(recipe.kcal_per_100g * factor, 2)
        protein_g = round(recipe.protein_per_100g * factor, 2)
        fat_g = round(recipe.fat_per_100g * factor, 2)
        carbs_g = round(recipe.carbs_per_100g * factor, 2)
    else:
        qty = payload.quantity_g if payload.quantity_g is not None else 1.0
        kcal = round(payload.kcal or 0.0, 2)
        protein_g = round(payload.protein_g or 0.0, 2)
        fat_g = round(payload.fat_g or 0.0, 2)
        carbs_g = round(payload.carbs_g or 0.0, 2)

    log = FoodLog(
        user_id=current_user.id,
        logged_date=payload.logged_date,
        logged_time=payload.logged_time,
        food_id=payload.food_id,
        recipe_id=payload.recipe_id,
        custom_name=payload.custom_name.strip() if payload.custom_name else None,
        quantity_g=qty,
        kcal=kcal,
        protein_g=protein_g,
        fat_g=fat_g,
        carbs_g=carbs_g,
    )
    db.add(log)
    await db.commit()
    await db.refresh(log)
    return _serialize_log_item(log, food, recipe)


@router.post(
    "/batch",
    response_model=FoodLogBatchCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def batch_create_food_logs(
    payload: FoodLogBatchCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FoodLogBatchCreateResponse:
    """Atomically insert a meal basket of food/recipe/free log items in one transaction."""
    food_ids = list({item.food_id for item in payload.items if item.food_id is not None})
    recipe_ids = list({item.recipe_id for item in payload.items if item.recipe_id is not None})

    foods_map: dict[UUID, Food] = {}
    if food_ids:
        res = await db.execute(select(Food).where(Food.id.in_(food_ids)))
        foods_map = {f.id: f for f in res.scalars().all()}
        for fid in food_ids:
            f = foods_map.get(fid)
            if f is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Aliment introuvable",
                )
            if f.created_by_user_id is not None and f.created_by_user_id != current_user.id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Accès refusé à cet aliment privé",
                )

    recipes_map: dict[UUID, Recipe] = {}
    if recipe_ids:
        res = await db.execute(select(Recipe).where(Recipe.id.in_(recipe_ids)))
        recipes_map = {r.id: r for r in res.scalars().all()}
        for rid in recipe_ids:
            r = recipes_map.get(rid)
            if r is None:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Recette introuvable",
                )
            if r.created_by_user_id != current_user.id and not r.is_shared:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Accès refusé à cette recette privée",
                )

    created_logs: list[FoodLog] = []
    for item in payload.items:
        if item.food_id is not None:
            food = foods_map[item.food_id]
            qty = item.quantity_g or 100.0
            factor = qty / 100.0
            kcal = round(food.kcal_per_100g * factor, 2)
            protein_g = round(food.protein_per_100g * factor, 2)
            fat_g = round(food.fat_per_100g * factor, 2)
            carbs_g = round(food.carbs_per_100g * factor, 2)
        elif item.recipe_id is not None:
            recipe = recipes_map[item.recipe_id]
            qty = item.quantity_g or 100.0
            factor = qty / 100.0
            kcal = round(recipe.kcal_per_100g * factor, 2)
            protein_g = round(recipe.protein_per_100g * factor, 2)
            fat_g = round(recipe.fat_per_100g * factor, 2)
            carbs_g = round(recipe.carbs_per_100g * factor, 2)
        else:
            qty = item.quantity_g if item.quantity_g is not None else 1.0
            kcal = round(item.kcal or 0.0, 2)
            protein_g = round(item.protein_g or 0.0, 2)
            fat_g = round(item.fat_g or 0.0, 2)
            carbs_g = round(item.carbs_g or 0.0, 2)

        log = FoodLog(
            user_id=current_user.id,
            logged_date=payload.logged_date,
            logged_time=payload.logged_time,
            food_id=item.food_id,
            recipe_id=item.recipe_id,
            custom_name=item.custom_name.strip() if item.custom_name else None,
            quantity_g=qty,
            kcal=kcal,
            protein_g=protein_g,
            fat_g=fat_g,
            carbs_g=carbs_g,
        )
        db.add(log)
        created_logs.append(log)

    await db.commit()
    for log in created_logs:
        await db.refresh(log)

    totals_res = await db.execute(
        select(
            func.sum(FoodLog.kcal),
            func.sum(FoodLog.protein_g),
            func.sum(FoodLog.fat_g),
            func.sum(FoodLog.carbs_g),
        ).where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date == payload.logged_date,
        )
    )
    row = totals_res.one()
    totals = MacroSummary(
        kcal=round(float(row[0] or 0.0), 1),
        protein_g=round(float(row[1] or 0.0), 1),
        fat_g=round(float(row[2] or 0.0), 1),
        carbs_g=round(float(row[3] or 0.0), 1),
    )

    entries = await _load_enriched_logs(db, created_logs)
    return FoodLogBatchCreateResponse(created_entries=entries, totals=totals)


async def _get_owned_log(
    db: AsyncSession,
    log_id: UUID,
    user_id: UUID,
) -> FoodLog:
    res = await db.execute(select(FoodLog).where(FoodLog.id == log_id))
    log = res.scalar_one_or_none()
    if log is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Entrée introuvable",
        )
    if log.user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé à cette entrée",
        )
    return log


@router.put("/{log_id}", response_model=FoodLogItem)
async def update_food_log(
    log_id: UUID,
    payload: FoodLogUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FoodLogItem:
    """Update a food log entry, recalculating macros if linked to a food/recipe."""
    log = await _get_owned_log(db, log_id, current_user.id)

    if payload.logged_date is not None:
        log.logged_date = payload.logged_date
    if payload.logged_time is not None:
        log.logged_time = payload.logged_time
    if payload.custom_name is not None:
        log.custom_name = payload.custom_name.strip() or None

    food: Food | None = None
    recipe: Recipe | None = None
    relinked_food = False

    if payload.food_id is not None:
        res = await db.execute(select(Food).where(Food.id == payload.food_id))
        food = res.scalar_one_or_none()
        if food is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Aliment introuvable",
            )
        log.food_id = payload.food_id
        log.recipe_id = None
        log.custom_name = None
        relinked_food = True
    elif log.food_id is not None:
        res = await db.execute(select(Food).where(Food.id == log.food_id))
        food = res.scalar_one_or_none()
    elif log.recipe_id is not None:
        res = await db.execute(select(Recipe).where(Recipe.id == log.recipe_id))
        recipe = res.scalar_one_or_none()

    if payload.quantity_g is not None:
        log.quantity_g = payload.quantity_g

    if payload.quantity_g is not None or relinked_food:
        if food is not None:
            factor = log.quantity_g / 100.0
            log.kcal = round(food.kcal_per_100g * factor, 2)
            log.protein_g = round(food.protein_per_100g * factor, 2)
            log.fat_g = round(food.fat_per_100g * factor, 2)
            log.carbs_g = round(food.carbs_per_100g * factor, 2)
        elif recipe is not None:
            factor = log.quantity_g / 100.0
            log.kcal = round(recipe.kcal_per_100g * factor, 2)
            log.protein_g = round(recipe.protein_per_100g * factor, 2)
            log.fat_g = round(recipe.fat_per_100g * factor, 2)
            log.carbs_g = round(recipe.carbs_per_100g * factor, 2)

    if food is None and recipe is None:
        if payload.kcal is not None:
            log.kcal = round(payload.kcal, 2)
        if payload.protein_g is not None:
            log.protein_g = round(payload.protein_g, 2)
        if payload.fat_g is not None:
            log.fat_g = round(payload.fat_g, 2)
        if payload.carbs_g is not None:
            log.carbs_g = round(payload.carbs_g, 2)

    await db.commit()
    await db.refresh(log)
    return _serialize_log_item(log, food, recipe)


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_food_log(
    log_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Delete a food log entry owned by the current user."""
    log = await _get_owned_log(db, log_id, current_user.id)
    await db.delete(log)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/copy", response_model=list[FoodLogItem], status_code=status.HTTP_201_CREATED)
async def copy_food_logs(
    payload: FoodLogCopyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FoodLogItem]:
    """Duplicate selected log entries or a source date/time range to target_date."""
    stmt = select(FoodLog).where(FoodLog.user_id == current_user.id)
    if payload.log_ids:
        stmt = stmt.where(FoodLog.id.in_(payload.log_ids))
    else:
        stmt = stmt.where(FoodLog.logged_date == payload.source_date)
        if payload.start_time is not None:
            stmt = stmt.where(FoodLog.logged_time >= payload.start_time)
        if payload.end_time is not None:
            stmt = stmt.where(FoodLog.logged_time <= payload.end_time)

    stmt = stmt.order_by(FoodLog.logged_time.asc(), FoodLog.created_at.asc())
    res = await db.execute(stmt)
    source_logs = list(res.scalars().all())

    if not source_logs:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aucune entrée trouvée à copier",
        )

    copied_logs: list[FoodLog] = []
    for src in source_logs:
        new_log = FoodLog(
            user_id=current_user.id,
            logged_date=payload.target_date,
            logged_time=payload.target_time or src.logged_time,
            food_id=src.food_id,
            recipe_id=src.recipe_id,
            custom_name=src.custom_name,
            quantity_g=src.quantity_g,
            kcal=src.kcal,
            protein_g=src.protein_g,
            fat_g=src.fat_g,
            carbs_g=src.carbs_g,
        )
        db.add(new_log)
        copied_logs.append(new_log)

    await db.commit()
    for item in copied_logs:
        await db.refresh(item)

    return await _load_enriched_logs(db, copied_logs)


@router.post("/move", response_model=list[FoodLogItem])
async def move_food_logs(
    payload: FoodLogMoveRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[FoodLogItem]:
    """Move selected log entries to target_date (and optional target_time) in one transaction."""
    res = await db.execute(
        select(FoodLog)
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.id.in_(payload.log_ids),
        )
        .order_by(FoodLog.logged_time.asc(), FoodLog.created_at.asc())
    )
    source_logs = list(res.scalars().all())
    if not source_logs:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aucune entrée trouvée à déplacer",
        )

    moved_logs: list[FoodLog] = []
    for src in source_logs:
        new_log = FoodLog(
            user_id=current_user.id,
            logged_date=payload.target_date,
            logged_time=payload.target_time or src.logged_time,
            food_id=src.food_id,
            recipe_id=src.recipe_id,
            custom_name=src.custom_name,
            quantity_g=src.quantity_g,
            kcal=src.kcal,
            protein_g=src.protein_g,
            fat_g=src.fat_g,
            carbs_g=src.carbs_g,
        )
        db.add(new_log)
        moved_logs.append(new_log)
        await db.delete(src)

    await db.commit()
    for item in moved_logs:
        await db.refresh(item)

    return await _load_enriched_logs(db, moved_logs)


@router.post("/batch-delete", response_model=FoodLogBatchDeleteResponse)
async def batch_delete_food_logs(
    payload: FoodLogBatchDeleteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FoodLogBatchDeleteResponse:
    """Batch delete selected log entries owned by the current user."""
    res = await db.execute(
        delete(FoodLog).where(
            FoodLog.user_id == current_user.id,
            FoodLog.id.in_(payload.log_ids),
        )
    )
    await db.commit()
    return FoodLogBatchDeleteResponse(deleted_count=res.rowcount or 0)


@router.get("/summary", response_model=list[DaySummaryItem])
async def get_logs_summary(
    start_date: date = Query(...),
    end_date: date = Query(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[DaySummaryItem]:
    """Return daily macro aggregations over [start_date, end_date]."""
    stmt = (
        select(
            FoodLog.logged_date,
            func.sum(FoodLog.kcal).label("kcal"),
            func.sum(FoodLog.protein_g).label("protein_g"),
            func.sum(FoodLog.fat_g).label("fat_g"),
            func.sum(FoodLog.carbs_g).label("carbs_g"),
            func.count(FoodLog.id).label("entries_count"),
        )
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date >= start_date,
            FoodLog.logged_date <= end_date,
        )
        .group_by(FoodLog.logged_date)
        .order_by(FoodLog.logged_date.asc())
    )
    res = await db.execute(stmt)
    return [
        DaySummaryItem(
            date=row.logged_date,
            kcal=round(float(row.kcal or 0.0), 1),
            protein_g=round(float(row.protein_g or 0.0), 1),
            fat_g=round(float(row.fat_g or 0.0), 1),
            carbs_g=round(float(row.carbs_g or 0.0), 1),
            entries_count=int(row.entries_count or 0),
        )
        for row in res.all()
    ]
