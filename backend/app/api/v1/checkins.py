from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.profile import _get_or_create_profile
from app.core.database import get_db
from app.models.tracking import FoodLog, WeeklyCheckin, WeightLog
from app.models.user import User
from app.schemas.checkins import (
    AnalyticsPoint,
    CheckinPreviewResponse,
    WeeklyCheckinResponse,
)
from app.services.tdee_engine import compute_adaptive_checkin

router = APIRouter(prefix="/checkins", tags=["checkins"])


@router.get("/preview", response_model=CheckinPreviewResponse)
async def preview_checkin(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CheckinPreviewResponse:
    """Compute adaptive TDEE and macro recommendations without persisting."""
    profile = await _get_or_create_profile(db, current_user)
    comp = await compute_adaptive_checkin(db, profile)
    return CheckinPreviewResponse(
        checkin_date=comp.checkin_date,
        period_start=comp.period_start,
        period_end=comp.period_end,
        avg_intake_kcal=comp.avg_intake_kcal,
        days_logged_count=comp.days_logged_count,
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
    """Persist weekly check-in and update user profile TDEE and macro targets."""
    profile = await _get_or_create_profile(db, current_user)
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
        )
        .order_by(desc(WeeklyCheckin.checkin_date), desc(WeeklyCheckin.created_at))
    )
    return list(res.scalars().all())


@router.get("/analytics", response_model=list[AnalyticsPoint])
async def get_analytics(
    days: int = Query(default=30, ge=7, le=365),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[AnalyticsPoint]:
    """Return daily intake, weight, trend weight, and estimated TDEE series."""
    profile = await _get_or_create_profile(db, current_user)
    end_date = date.today()
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

    checkins_res = await db.execute(
        select(WeeklyCheckin)
        .where(
            WeeklyCheckin.user_id == current_user.id,
            WeeklyCheckin.accepted.is_(True),
            WeeklyCheckin.checkin_date <= end_date,
        )
        .order_by(WeeklyCheckin.checkin_date.asc())
    )
    checkins = list(checkins_res.scalars().all())

    points: list[AnalyticsPoint] = []
    checkin_idx = 0
    fallback_tdee = round(
        profile.current_tdee_kcal
        if profile.current_tdee_kcal > 0
        else max(profile.initial_tdee_kcal, 0.0),
        0,
    )
    current_est_tdee = round(
        profile.initial_tdee_kcal
        if profile.initial_tdee_kcal > 0
        else fallback_tdee,
        0,
    )
    current_target_kcal = round(profile.current_calorie_target, 0)

    for offset in range(days):
        day = start_date + timedelta(days=offset)
        while (
            checkin_idx < len(checkins)
            and checkins[checkin_idx].checkin_date <= day
        ):
            if checkins[checkin_idx].calculated_tdee_kcal > 0:
                current_est_tdee = round(
                    checkins[checkin_idx].calculated_tdee_kcal, 0
                )
            if checkins[checkin_idx].new_calorie_target > 0:
                current_target_kcal = round(
                    checkins[checkin_idx].new_calorie_target, 0
                )
            checkin_idx += 1

        if not checkins or current_est_tdee <= 0:
            current_est_tdee = fallback_tdee
        if not checkins:
            current_target_kcal = round(profile.current_calorie_target, 0)

        w_entry = weight_by_day.get(day)
        points.append(
            AnalyticsPoint(
                date=day,
                intake_kcal=intake_by_day.get(day, 0.0),
                target_kcal=current_target_kcal,
                weight_kg=w_entry.weight_kg if w_entry else None,
                trend_weight_kg=w_entry.trend_weight_kg if w_entry else None,
                estimated_tdee_kcal=current_est_tdee,
            )
        )

    return points
