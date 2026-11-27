from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Literal
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tracking import FoodLog, WeeklyCheckin, WeightLog
from app.models.user import (
    DietStyle,
    ProteinPreference,
    Sex,
    UserProfile,
)

EWMA_ALPHA = 0.1
KCAL_PER_KG = 7700.0
MIN_VALID_INTAKE_RATIO = 0.4
MAX_WEEKLY_TDEE_DELTA = 150.0
DEFAULT_WINDOW_DAYS = 21

PROTEIN_FACTORS: dict[ProteinPreference, float] = {
    ProteinPreference.MODERATE: 1.7,
    ProteinPreference.HIGH: 2.0,
    ProteinPreference.EXTRA_HIGH: 2.3,
}

FAT_RATIOS: dict[DietStyle, float] = {
    DietStyle.BALANCED: 0.30,
    DietStyle.LOW_FAT: 0.20,
    DietStyle.LOW_CARB: 0.45,
}


@dataclass(slots=True)
class MacroTargets:
    """Computed daily calorie and macronutrient targets."""

    calorie_target: float
    protein_g: float
    fat_g: float
    carbs_g: float


@dataclass(slots=True)
class DateTargets:
    """Resolved calorie and macro targets effective on a given date."""

    calorie_target: float
    protein_g: float
    fat_g: float
    carbs_g: float
    tdee_kcal: float


async def get_targets_for_date(
    db: AsyncSession,
    user_id: UUID,
    target_date: date,
    profile: UserProfile,
) -> DateTargets:
    """Resolve macro and calorie targets active on target_date without retroactive overwrite."""
    res = await db.execute(
        select(WeeklyCheckin)
        .where(
            WeeklyCheckin.user_id == user_id,
            WeeklyCheckin.accepted.is_(True),
            WeeklyCheckin.checkin_date <= target_date,
        )
        .order_by(
            desc(WeeklyCheckin.checkin_date),
            desc(WeeklyCheckin.created_at),
        )
        .limit(1)
    )
    checkin = res.scalar_one_or_none()
    if checkin is not None:
        return DateTargets(
            calorie_target=checkin.new_calorie_target,
            protein_g=checkin.new_protein_g,
            fat_g=checkin.new_fat_g,
            carbs_g=checkin.new_carbs_g,
            tdee_kcal=checkin.calculated_tdee_kcal,
        )
    return DateTargets(
        calorie_target=profile.current_calorie_target,
        protein_g=profile.current_protein_g,
        fat_g=profile.current_fat_g,
        carbs_g=profile.current_carbs_g,
        tdee_kcal=profile.current_tdee_kcal,
    )


@dataclass(slots=True)
class CheckinComputation:
    """Result of an adaptive TDEE & macro check-in calculation."""

    checkin_date: date
    period_start: date
    period_end: date
    avg_intake_kcal: float
    days_logged_count: int
    start_trend_weight_kg: float
    end_trend_weight_kg: float
    previous_tdee_kcal: float
    calculated_tdee_kcal: float
    tdee_delta_kcal: float
    new_calorie_target: float
    new_protein_g: float
    new_fat_g: float
    new_carbs_g: float
    confidence: Literal["low", "medium", "high"]
    is_due: bool


async def recalculate_weight_trends(
    db: AsyncSession,
    user_id: UUID,
) -> list[WeightLog]:
    """Recompute EWMA trend_weight_kg across all weight logs of a user."""
    result = await db.execute(
        select(WeightLog)
        .where(WeightLog.user_id == user_id)
        .order_by(WeightLog.measured_at.asc())
    )
    logs = list(result.scalars().all())
    if not logs:
        return []

    trend = logs[0].weight_kg
    logs[0].trend_weight_kg = round(trend, 3)

    for idx in range(1, len(logs)):
        delta_days = max(
            (logs[idx].measured_at - logs[idx - 1].measured_at).total_seconds()
            / 86400.0,
            1.0,
        )
        alpha_eff = 1.0 - (1.0 - EWMA_ALPHA) ** delta_days
        trend = trend + alpha_eff * (logs[idx].weight_kg - trend)
        logs[idx].trend_weight_kg = round(trend, 3)

    await db.commit()
    return logs


def calculate_macro_targets(
    profile: UserProfile,
    calculated_tdee: float,
    current_trend_weight_kg: float,
) -> MacroTargets:
    """Compute calorie and macro targets from adaptive TDEE and user preferences."""
    raw_target = round(
        calculated_tdee + (profile.target_rate_kg_per_week * KCAL_PER_KG / 7.0)
    )
    safety_floor = 1200.0 if profile.sex == Sex.FEMALE else 1500.0
    target_kcal = float(max(safety_floor, raw_target))

    protein_factor = PROTEIN_FACTORS[profile.protein_preference]
    protein_g = round(current_trend_weight_kg * protein_factor, 1)
    remaining_kcal = max(target_kcal - protein_g * 4.0, 200.0)

    if profile.diet_style == DietStyle.LOW_FAT:
        min_fat_kcal = current_trend_weight_kg * 0.6 * 9.0
        fat_kcal = min(remaining_kcal, max(target_kcal * 0.20, min_fat_kcal))
    elif profile.diet_style == DietStyle.LOW_CARB:
        fat_kcal = min(remaining_kcal, target_kcal * FAT_RATIOS[DietStyle.LOW_CARB])
    else:
        fat_kcal = min(remaining_kcal, target_kcal * FAT_RATIOS[DietStyle.BALANCED])

    fat_g = round(fat_kcal / 9.0, 1)
    carbs_g = round(max(remaining_kcal - fat_kcal, 0.0) / 4.0, 1)

    return MacroTargets(
        calorie_target=round(target_kcal, 0),
        protein_g=protein_g,
        fat_g=fat_g,
        carbs_g=carbs_g,
    )


async def compute_adaptive_checkin(
    db: AsyncSession,
    profile: UserProfile,
    reference_date: date | None = None,
    window_days: int = DEFAULT_WINDOW_DAYS,
) -> CheckinComputation:
    """Analyze intake and EWMA weight trend over a 14-21 day window."""
    today = date.today()
    ref_date = min(reference_date, today) if reference_date is not None else today
    # Exclude today (incomplete) and any future dates: only completed past days (< today).
    period_end = ref_date - timedelta(days=1)
    period_start = period_end - timedelta(days=window_days - 1)

    daily_intake_res = await db.execute(
        select(
            FoodLog.logged_date,
            func.sum(FoodLog.kcal).label("day_kcal"),
        )
        .where(
            FoodLog.user_id == profile.user_id,
            FoodLog.logged_date >= period_start,
            FoodLog.logged_date <= period_end,
        )
        .group_by(FoodLog.logged_date)
    )

    min_valid_kcal = MIN_VALID_INTAKE_RATIO * profile.current_tdee_kcal
    valid_intakes = [
        float(row.day_kcal)
        for row in daily_intake_res.all()
        if row.day_kcal is not None
        and float(row.day_kcal) > 0.0
        and float(row.day_kcal) >= min_valid_kcal
    ]
    days_logged_count = len(valid_intakes)
    avg_intake_kcal = (
        round(sum(valid_intakes) / days_logged_count, 1)
        if days_logged_count > 0
        else 0.0
    )

    window_start_dt = datetime.combine(period_start, time.min).astimezone()
    ref_end_dt = datetime.combine(ref_date, time.max).astimezone()

    weights_res = await db.execute(
        select(WeightLog)
        .where(
            WeightLog.user_id == profile.user_id,
            WeightLog.measured_at >= window_start_dt,
            WeightLog.measured_at <= ref_end_dt,
        )
        .order_by(WeightLog.measured_at.asc())
    )
    weights_in_window = list(weights_res.scalars().all())

    if weights_in_window:
        start_trend = (
            weights_in_window[0].trend_weight_kg
            if weights_in_window[0].trend_weight_kg is not None
            else weights_in_window[0].weight_kg
        )
        end_trend = (
            weights_in_window[-1].trend_weight_kg
            if weights_in_window[-1].trend_weight_kg is not None
            else weights_in_window[-1].weight_kg
        )
    else:
        latest_weight_res = await db.execute(
            select(WeightLog)
            .where(
                WeightLog.user_id == profile.user_id,
                WeightLog.measured_at <= ref_end_dt,
            )
            .order_by(desc(WeightLog.measured_at))
            .limit(1)
        )
        latest_weight = latest_weight_res.scalar_one_or_none()
        fallback_weight = (
            (latest_weight.trend_weight_kg or latest_weight.weight_kg)
            if latest_weight is not None
            else 70.0
        )
        start_trend = fallback_weight
        end_trend = fallback_weight

    previous_tdee = round(profile.current_tdee_kcal, 0)

    if days_logged_count < 5 or len(weights_in_window) < 3:
        confidence: Literal["low", "medium", "high"] = "low"
        calculated_tdee = previous_tdee
    else:
        confidence = "high" if days_logged_count >= 12 else "medium"
        days_span = max(
            (
                weights_in_window[-1].measured_at.date()
                - weights_in_window[0].measured_at.date()
            ).days,
            1,
        )
        raw_tdee = avg_intake_kcal - (
            ((end_trend - start_trend) * KCAL_PER_KG) / days_span
        )
        weight = min(days_logged_count / 14.0, 1.0)
        blended_tdee = previous_tdee * (1.0 - weight) + raw_tdee * weight
        delta = max(
            -MAX_WEEKLY_TDEE_DELTA,
            min(MAX_WEEKLY_TDEE_DELTA, blended_tdee - previous_tdee),
        )
        calculated_tdee = round(max(1000.0, previous_tdee + delta), 0)

    macros = calculate_macro_targets(profile, calculated_tdee, end_trend)

    last_checkin_res = await db.execute(
        select(WeeklyCheckin.checkin_date)
        .where(
            WeeklyCheckin.user_id == profile.user_id,
            WeeklyCheckin.accepted.is_(True),
        )
        .order_by(desc(WeeklyCheckin.checkin_date))
        .limit(1)
    )
    last_checkin_date = last_checkin_res.scalar_one_or_none()
    today_wd = ref_date.weekday()
    expected_wd = profile.checkin_day
    eve_wd = (expected_wd - 1) % 7
    is_window_open = today_wd == expected_wd or today_wd == eve_wd
    no_recent_checkin = (
        last_checkin_date is None or (ref_date - last_checkin_date).days >= 5
    )
    is_due = is_window_open and no_recent_checkin

    return CheckinComputation(
        checkin_date=ref_date,
        period_start=period_start,
        period_end=period_end,
        avg_intake_kcal=avg_intake_kcal,
        days_logged_count=days_logged_count,
        start_trend_weight_kg=round(start_trend, 2),
        end_trend_weight_kg=round(end_trend, 2),
        previous_tdee_kcal=previous_tdee,
        calculated_tdee_kcal=calculated_tdee,
        tdee_delta_kcal=round(calculated_tdee - previous_tdee, 0),
        new_calorie_target=macros.calorie_target,
        new_protein_g=macros.protein_g,
        new_fat_g=macros.fat_g,
        new_carbs_g=macros.carbs_g,
        confidence=confidence,
        is_due=is_due,
    )
