from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.profile import _get_or_create_profile
from app.core.database import get_db
from app.models.tracking import FoodLog, TargetHistory, WeeklyCheckin, WeightLog
from app.models.user import User
from app.schemas.checkins import (
    AnalyticsPoint,
    CheckinPreviewResponse,
    WeeklyCheckinResponse,
)
from app.services.tdee_engine import (
    compute_adaptive_checkin,
    compute_daily_tdee_series,
    get_target_history_rows,
    is_real_weekly_checkin_clause,
    upsert_target_history,
)

router = APIRouter(prefix="/checkins", tags=["checkins"])


@router.get("/preview", response_model=CheckinPreviewResponse)
async def preview_checkin(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CheckinPreviewResponse:
    """Compute adaptive TDEE and macro recommendations without persisting targets."""
    profile = await _get_or_create_profile(db, current_user)
    comp = await compute_adaptive_checkin(db, profile)

    # Keep live daily TDEE fresh on profile without ever altering frozen weekly targets.
    if (
        comp.calculated_tdee_kcal > 0
        and round(profile.current_tdee_kcal, 0) != comp.calculated_tdee_kcal
    ):
        profile.current_tdee_kcal = comp.calculated_tdee_kcal
        await db.commit()

    return CheckinPreviewResponse(
        checkin_date=comp.checkin_date,
        period_start=comp.period_start,
        period_end=comp.period_end,
        avg_intake_kcal=comp.avg_intake_kcal,
        days_logged_count=comp.days_logged_count,
        valid_nutrition_days_21d=comp.valid_nutrition_days_21d,
        window_days=comp.window_days,
        start_trend_weight_kg=comp.start_trend_weight_kg,
        end_trend_weight_kg=comp.end_trend_weight_kg,
        previous_tdee_kcal=comp.previous_tdee_kcal,
        calculated_tdee_kcal=comp.calculated_tdee_kcal,
        tdee_delta_kcal=comp.tdee_delta_kcal,
        new_calorie_target=comp.new_calorie_target,
        new_protein_g=comp.new_protein_g,
        new_fat_g=comp.new_fat_g,
        new_carbs_g=comp.new_carbs_g,
        confidence=comp.confidence,
        is_due=comp.is_due,
    )


@router.post(
    "/accept",
    response_model=WeeklyCheckinResponse,
    status_code=status.HTTP_201_CREATED,
)
async def accept_checkin(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WeeklyCheckin:
    """Persist weekly check-in, update profile targets, and version target_history."""
    profile = await _get_or_create_profile(db, current_user)
    old_kcal = profile.current_calorie_target
    old_protein = profile.current_protein_g
    old_fat = profile.current_fat_g
    old_carbs = profile.current_carbs_g

    comp = await compute_adaptive_checkin(db, profile)
    if not comp.is_due:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Le check-in n'est disponible que la veille ou le jour prévu.",
        )

    checkin = WeeklyCheckin(
        user_id=current_user.id,
        checkin_date=comp.checkin_date,
        period_start=comp.period_start,
        period_end=comp.period_end,
        avg_intake_kcal=comp.avg_intake_kcal,
        days_logged_count=comp.days_logged_count,
        start_trend_weight_kg=comp.start_trend_weight_kg,
        end_trend_weight_kg=comp.end_trend_weight_kg,
        calculated_tdee_kcal=comp.calculated_tdee_kcal,
        new_calorie_target=comp.new_calorie_target,
        new_protein_g=comp.new_protein_g,
        new_fat_g=comp.new_fat_g,
        new_carbs_g=comp.new_carbs_g,
        accepted=True,
    )
    db.add(checkin)

    profile.current_tdee_kcal = comp.calculated_tdee_kcal
    profile.current_calorie_target = comp.new_calorie_target
    profile.current_protein_g = comp.new_protein_g
    profile.current_fat_g = comp.new_fat_g
    profile.current_carbs_g = comp.new_carbs_g

    await upsert_target_history(
        db,
        current_user.id,
        effective_from=comp.checkin_date,
        target_kcal=comp.new_calorie_target,
        target_protein_g=comp.new_protein_g,
        target_fat_g=comp.new_fat_g,
        target_carbs_g=comp.new_carbs_g,
        source="checkin",
        preserve_previous=(
            current_user.created_at.date(),
            old_kcal,
            old_protein,
            old_fat,
            old_carbs,
        ),
    )

    await db.commit()
    await db.refresh(checkin)
    return checkin


@router.get("", response_model=list[WeeklyCheckinResponse])
async def list_checkins(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[WeeklyCheckin]:
    """List accepted weekly check-ins ordered from newest to oldest."""
    res = await db.execute(
        select(WeeklyCheckin)
        .where(
            WeeklyCheckin.user_id == current_user.id,
            WeeklyCheckin.accepted.is_(True),
            is_real_weekly_checkin_clause(),
        )
        .order_by(desc(WeeklyCheckin.checkin_date), desc(WeeklyCheckin.created_at))
    )
    return list(res.scalars().all())


@router.get("/analytics", response_model=list[AnalyticsPoint])
async def get_analytics(
    days: int = Query(default=30, ge=0, le=3650),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[AnalyticsPoint]:
    """Return daily intake, weight, trend weight, versioned target, and daily adaptive TDEE."""
    profile = await _get_or_create_profile(db, current_user)
    end_date = date.today()
    if days == 0:
        min_weight_res = await db.execute(
            select(func.min(WeightLog.measured_at)).where(
                WeightLog.user_id == current_user.id
            )
        )
        min_food_res = await db.execute(
            select(func.min(FoodLog.logged_date)).where(
                FoodLog.user_id == current_user.id
            )
        )
        min_target_res = await db.execute(
            select(func.min(TargetHistory.effective_from)).where(
                TargetHistory.user_id == current_user.id
            )
        )
        candidates: list[date] = []
        min_w = min_weight_res.scalar_one_or_none()
        if min_w is not None:
            candidates.append(min_w.date())
        min_f = min_food_res.scalar_one_or_none()
        if min_f is not None:
            candidates.append(min_f)
        min_t = min_target_res.scalar_one_or_none()
        if min_t is not None:
            candidates.append(min_t)
        earliest = min(candidates) if candidates else (end_date - timedelta(days=29))
        earliest = min(earliest, end_date)
        computed_days = max(7, (end_date - earliest).days + 1)
        start_date = end_date - timedelta(days=min(computed_days, 3650) - 1)
        days = (end_date - start_date).days + 1
    else:
        days = max(7, days)
        start_date = end_date - timedelta(days=days - 1)

    intake_res = await db.execute(
        select(
            FoodLog.logged_date,
            func.sum(FoodLog.kcal).label("total_kcal"),
        )
        .where(
            FoodLog.user_id == current_user.id,
            FoodLog.logged_date >= start_date,
            FoodLog.logged_date <= end_date,
        )
        .group_by(FoodLog.logged_date)
    )
    intake_by_day = {
        row.logged_date: round(float(row.total_kcal or 0.0), 1)
        for row in intake_res.all()
    }

    start_dt = datetime.combine(start_date, time.min).astimezone()
    end_dt = datetime.combine(end_date, time.max).astimezone()
    weights_res = await db.execute(
        select(WeightLog)
        .where(
            WeightLog.user_id == current_user.id,
            WeightLog.measured_at >= start_dt,
            WeightLog.measured_at <= end_dt,
        )
        .order_by(WeightLog.measured_at.asc())
    )
    weight_by_day: dict[date, WeightLog] = {}
    for w in weights_res.scalars().all():
        weight_by_day[w.measured_at.date()] = w

    tdee_series = await compute_daily_tdee_series(
        db,
        profile,
        start_date=start_date,
        end_date=end_date,
    )
    if (
        tdee_series.latest_tdee_kcal > 0
        and round(profile.current_tdee_kcal, 0) != tdee_series.latest_tdee_kcal
    ):
        profile.current_tdee_kcal = tdee_series.latest_tdee_kcal
        await db.commit()

    # Batch-resolve versioned targets from target_history (zero N+1 queries, zero retroactive overwrite).
    history_rows = await get_target_history_rows(db, current_user.id, end_date)
    target_idx = 0
    fallback_target_kcal = round(
        history_rows[0].target_kcal
        if history_rows
        else profile.current_calorie_target,
        0,
    )
    current_target_kcal = fallback_target_kcal

    points: list[AnalyticsPoint] = []
    for offset in range(days):
        day = start_date + timedelta(days=offset)
        while (
            target_idx < len(history_rows)
            and history_rows[target_idx].effective_from <= day
        ):
            if history_rows[target_idx].target_kcal > 0:
                current_target_kcal = round(history_rows[target_idx].target_kcal, 0)
            target_idx += 1

        w_entry = weight_by_day.get(day)
        points.append(
            AnalyticsPoint(
                date=day,
                intake_kcal=intake_by_day.get(day, 0.0),
                target_kcal=current_target_kcal,
                weight_kg=w_entry.weight_kg if w_entry else None,
                trend_weight_kg=w_entry.trend_weight_kg if w_entry else None,
                estimated_tdee_kcal=tdee_series.daily_tdee.get(
                    day, tdee_series.latest_tdee_kcal
                ),
            )
        )

    return points
