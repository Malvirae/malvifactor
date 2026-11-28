from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.profile import _get_or_create_profile
from app.core.database import get_db
from app.models.tracking import FoodLog
from app.models.user import User
from app.schemas.dashboard import (
    WeeklyNutritionDay,
    WeeklyNutritionResponse,
    WeeklyNutritionTotals,
)
from app.services.tdee_engine import get_target_history_rows

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/weekly-nutrition", response_model=WeeklyNutritionResponse)
async def get_weekly_nutrition(
    reference_date: date | None = Query(
        default=None,
        description="Optional date inside the target calendar week (defaults to today)",
    ),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WeeklyNutritionResponse:
    """Return Monday -> Sunday consumed vs target macros for the Dashboard carousel."""
    today = date.today()
    ref = reference_date or today
    monday = ref - timedelta(days=ref.weekday())
    sunday = monday + timedelta(days=6)

    # Single aggregated query over food_logs (no join -> includes standard, custom,
    # recipes, and quick_add entries where food_id IS NULL).
    logs_res = await db.execute(
        select(
            FoodLog.logged_date,
            func.coalesce(func.sum(FoodLog.kcal), 0.0).label("kcal"),
            func.coalesce(func.sum(FoodLog.protein_g), 0.0).label("protein_g"),
            func.coalesce(func.sum(FoodLog.fat_g), 0.0).label("fat_g"),
            func.coalesce(func.sum(FoodLog.carbs_g), 0.0).label("carbs_g"),
        )
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date >= monday,
            FoodLog.logged_date <= sunday,
        )
        .group_by(FoodLog.logged_date)
    )
    consumed_by_day: dict[date, tuple[float, float, float, float]] = {
        row.logged_date: (
            round(float(row.kcal or 0.0), 1),
            round(float(row.protein_g or 0.0), 1),
            round(float(row.fat_g or 0.0), 1),
            round(float(row.carbs_g or 0.0), 1),
        )
        for row in logs_res.all()
    }

    profile = await _get_or_create_profile(db, current_user)
    history_rows = await get_target_history_rows(db, current_user.id, sunday)

    # Resolve versioned daily targets in O(N) without retroactive overwrite.
    hist_idx = 0
    active_target: tuple[float, float, float, float] | None = None
    earliest_target: tuple[float, float, float, float] = (
        (
            round(history_rows[0].target_kcal, 1),
            round(history_rows[0].target_protein_g, 1),
            round(history_rows[0].target_fat_g, 1),
            round(history_rows[0].target_carbs_g, 1),
        )
        if history_rows
        else (
            round(profile.current_calorie_target, 1),
            round(profile.current_protein_g, 1),
            round(profile.current_fat_g, 1),
            round(profile.current_carbs_g, 1),
        )
    )
    current_profile_target = (
        round(profile.current_calorie_target, 1),
        round(profile.current_protein_g, 1),
        round(profile.current_fat_g, 1),
        round(profile.current_carbs_g, 1),
    )

    days: list[WeeklyNutritionDay] = []
    sum_c_kcal = 0.0
    sum_c_p = 0.0
    sum_c_f = 0.0
    sum_c_c = 0.0
    sum_t_kcal = 0.0
    sum_t_p = 0.0
    sum_t_f = 0.0
    sum_t_c = 0.0

    for offset in range(7):
        day = monday + timedelta(days=offset)
        while (
            hist_idx < len(history_rows)
            and history_rows[hist_idx].effective_from <= day
        ):
            row = history_rows[hist_idx]
            active_target = (
                round(row.target_kcal, 1),
                round(row.target_protein_g, 1),
                round(row.target_fat_g, 1),
                round(row.target_carbs_g, 1),
            )
            hist_idx += 1

        if day > today:
            t_kcal, t_p, t_f, t_c = (
                current_profile_target
                if current_profile_target[0] > 0
                else (active_target or earliest_target)
            )
        else:
            t_kcal, t_p, t_f, t_c = active_target or earliest_target

        c_kcal, c_p, c_f, c_c = consumed_by_day.get(day, (0.0, 0.0, 0.0, 0.0))

        sum_c_kcal += c_kcal
        sum_c_p += c_p
        sum_c_f += c_f
        sum_c_c += c_c
        sum_t_kcal += t_kcal
        sum_t_p += t_p
        sum_t_f += t_f
        sum_t_c += t_c

        days.append(
            WeeklyNutritionDay(
                date=day,
                day_of_week=offset + 1,
                is_today=(day == today),
                is_future=(day > today),
                consumed_kcal=c_kcal,
                consumed_protein_g=c_p,
                consumed_fat_g=c_f,
                consumed_carbs_g=c_c,
                target_kcal=t_kcal,
                target_protein_g=t_p,
                target_fat_g=t_f,
                target_carbs_g=t_c,
            )
        )

    return WeeklyNutritionResponse(
        week_start=monday,
        week_end=sunday,
        days=days,
        week_totals=WeeklyNutritionTotals(
            consumed_kcal=round(sum_c_kcal, 1),
            consumed_protein_g=round(sum_c_p, 1),
            consumed_fat_g=round(sum_c_f, 1),
            consumed_carbs_g=round(sum_c_c, 1),
            target_kcal=round(sum_t_kcal, 1),
            target_protein_g=round(sum_t_p, 1),
            target_fat_g=round(sum_t_f, 1),
            target_carbs_g=round(sum_t_c, 1),
        ),
    )
