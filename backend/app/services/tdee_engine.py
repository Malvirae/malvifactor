from bisect import bisect_left, bisect_right
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Literal
from uuid import UUID

from sqlalchemy import and_, asc, desc, func, not_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tracking import FoodLog, TargetHistory, WeeklyCheckin, WeightLog
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
MIN_NUTRITION_DAYS_FOR_ADAPTATION = 5
CALIBRATED_NUTRITION_DAYS = 14
DAILY_TDEE_ALPHA = 0.14
MIN_DAILY_TDEE_DELTA = 12.0
MAX_DAILY_TDEE_DELTA = 22.0

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


@dataclass(slots=True)
class DailyTdeeSeriesResult:
    """Day-by-day adaptive TDEE time-series and trailing 21-day window stats."""

    daily_tdee: dict[date, float]
    latest_tdee_kcal: float
    valid_nutrition_days_21d: int
    window_days: int
    avg_intake_21d: float
    start_trend_weight_kg: float
    end_trend_weight_kg: float
    weights_in_window_count: int


def is_real_weekly_checkin_clause():
    """Filter out legacy synthetic manual-profile rows from weekly_checkins."""
    return not_(
        and_(
            WeeklyCheckin.period_start == WeeklyCheckin.checkin_date,
            WeeklyCheckin.period_end == WeeklyCheckin.checkin_date,
            WeeklyCheckin.days_logged_count == 0,
        )
    )


async def upsert_target_history(
    db: AsyncSession,
    user_id: UUID,
    *,
    effective_from: date,
    target_kcal: float,
    target_protein_g: float,
    target_fat_g: float,
    target_carbs_g: float,
    source: Literal["initial", "checkin", "manual"],
    preserve_previous: tuple[date, float, float, float, float] | None = None,
) -> None:
    """Record target macros from effective_from without modifying earlier dates.

    If a row already exists for the exact same effective_from date, only that row
    is updated. Earlier history rows are strictly immutable.
    """
    if target_kcal <= 0:
        return

    if preserve_previous is not None:
        baseline_date, old_kcal, old_protein, old_fat, old_carbs = preserve_previous
        if old_kcal > 0:
            earlier_res = await db.execute(
                select(TargetHistory.id)
                .where(
                    TargetHistory.user_id == user_id,
                    TargetHistory.effective_from < effective_from,
                )
                .limit(1)
            )
            if earlier_res.scalar_one_or_none() is None:
                safe_baseline = min(
                    baseline_date, effective_from - timedelta(days=1)
                )
                db.add(
                    TargetHistory(
                        user_id=user_id,
                        effective_from=safe_baseline,
                        target_kcal=round(old_kcal, 1),
                        target_protein_g=round(old_protein, 1),
                        target_fat_g=round(old_fat, 1),
                        target_carbs_g=round(old_carbs, 1),
                        source="initial",
                    )
                )

    same_day_res = await db.execute(
        select(TargetHistory)
        .where(
            TargetHistory.user_id == user_id,
            TargetHistory.effective_from == effective_from,
        )
        .order_by(desc(TargetHistory.created_at))
        .limit(1)
    )
    existing = same_day_res.scalar_one_or_none()
    if existing is not None:
        existing.target_kcal = round(target_kcal, 1)
        existing.target_protein_g = round(target_protein_g, 1)
        existing.target_fat_g = round(target_fat_g, 1)
        existing.target_carbs_g = round(target_carbs_g, 1)
        existing.source = source
    else:
        db.add(
            TargetHistory(
                user_id=user_id,
                effective_from=effective_from,
                target_kcal=round(target_kcal, 1),
                target_protein_g=round(target_protein_g, 1),
                target_fat_g=round(target_fat_g, 1),
                target_carbs_g=round(target_carbs_g, 1),
                source=source,
            )
        )


async def get_target_history_rows(
    db: AsyncSession,
    user_id: UUID,
    up_to_date: date | None = None,
) -> list[TargetHistory]:
    """Return ordered target_history snapshots for a user (ascending effective_from)."""
    stmt = select(TargetHistory).where(TargetHistory.user_id == user_id)
    if up_to_date is not None:
        stmt = stmt.where(TargetHistory.effective_from <= up_to_date)
    stmt = stmt.order_by(
        asc(TargetHistory.effective_from),
        asc(TargetHistory.created_at),
    )
    res = await db.execute(stmt)
    return list(res.scalars().all())


async def get_targets_for_date(
    db: AsyncSession,
    user_id: UUID,
    target_date: date,
    profile: UserProfile,
) -> DateTargets:
    """Resolve macro and calorie targets active on target_date without retroactive overwrite."""
    res = await db.execute(
        select(TargetHistory)
        .where(
            TargetHistory.user_id == user_id,
            TargetHistory.effective_from <= target_date,
        )
        .order_by(
            desc(TargetHistory.effective_from),
            desc(TargetHistory.created_at),
        )
        .limit(1)
    )
    entry = res.scalar_one_or_none()
    if entry is not None:
        return DateTargets(
            calorie_target=entry.target_kcal,
            protein_g=entry.target_protein_g,
            fat_g=entry.target_fat_g,
            carbs_g=entry.target_carbs_g,
            tdee_kcal=profile.current_tdee_kcal,
        )

    # If target_date precedes the earliest recorded snapshot, preserve the earliest
    # baseline targets rather than leaking later check-in targets backward.
    oldest_res = await db.execute(
        select(TargetHistory)
        .where(TargetHistory.user_id == user_id)
        .order_by(
            asc(TargetHistory.effective_from),
            asc(TargetHistory.created_at),
        )
        .limit(1)
    )
    oldest = oldest_res.scalar_one_or_none()
    if oldest is not None:
        return DateTargets(
            calorie_target=oldest.target_kcal,
            protein_g=oldest.target_protein_g,
            fat_g=oldest.target_fat_g,
            carbs_g=oldest.target_carbs_g,
            tdee_kcal=profile.current_tdee_kcal,
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
    valid_nutrition_days_21d: int
    window_days: int
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


def _interpolate_trend(
    target_day: date,
    weight_dates: list[date],
    weight_trends: list[float],
) -> float:
    """Linearly interpolate EWMA trend weight on target_day from known weigh-in dates."""
    if not weight_dates:
        return 70.0
    if target_day <= weight_dates[0]:
        return weight_trends[0]
    if target_day >= weight_dates[-1]:
        return weight_trends[-1]

    idx = bisect_left(weight_dates, target_day)
    if weight_dates[idx] == target_day:
        return weight_trends[idx]

    d0, v0 = weight_dates[idx - 1], weight_trends[idx - 1]
    d1, v1 = weight_dates[idx], weight_trends[idx]
    span = max((d1 - d0).days, 1)
    frac = (target_day - d0).days / float(span)
    return v0 + (v1 - v0) * frac


async def compute_daily_tdee_series(
    db: AsyncSession,
    profile: UserProfile,
    *,
    start_date: date | None = None,
    end_date: date | None = None,
    window_days: int = DEFAULT_WINDOW_DAYS,
) -> DailyTdeeSeriesResult:
    """Compute a smooth day-by-day adaptive TDEE series over completed past days (< today).

    - Sums ALL food_logs per day (standard, custom, recipe, and quick_add where food_id IS NULL).
    - Strictly excludes today and any future dates from nutrition aggregation.
    - Starts adapting smoothly at >= 5 valid nutrition days in the 21-day rolling window,
      ramping progressively from day 5 to day 14, then full responsiveness thereafter.
    - Never mutates weekly macro targets or target_history.
    """
    today = date.today()
    ref_date = min(end_date, today) if end_date is not None else today
    last_completed_day = ref_date - timedelta(days=1)

    base_tdee = round(
        profile.initial_tdee_kcal
        if profile.initial_tdee_kcal > 0
        else max(profile.current_tdee_kcal, 0.0),
        0,
    )

    # Query ALL food_logs strictly before ref_date (< today), with NO join on foods/recipes
    # so quick_add entries (food_id IS NULL, recipe_id IS NULL) are 100% included.
    daily_intake_res = await db.execute(
        select(
            FoodLog.logged_date,
            func.sum(FoodLog.kcal).label("day_kcal"),
        )
        .where(
            FoodLog.user_id == profile.user_id,
            FoodLog.logged_date <= last_completed_day,
        )
        .group_by(FoodLog.logged_date)
        .order_by(FoodLog.logged_date.asc())
    )
    all_intake_rows = [
        (row.logged_date, float(row.day_kcal))
        for row in daily_intake_res.all()
        if row.day_kcal is not None and float(row.day_kcal) > 0.0
    ]

    min_valid_kcal = MIN_VALID_INTAKE_RATIO * max(base_tdee, 1200.0)
    valid_food_dates: list[date] = []
    valid_food_kcals: list[float] = []
    for d, kcal in all_intake_rows:
        if kcal >= min_valid_kcal:
            valid_food_dates.append(d)
            valid_food_kcals.append(kcal)

    ref_end_dt = datetime.combine(ref_date, time.max).astimezone()
    weights_res = await db.execute(
        select(WeightLog)
        .where(
            WeightLog.user_id == profile.user_id,
            WeightLog.measured_at <= ref_end_dt,
        )
        .order_by(WeightLog.measured_at.asc())
    )
    weight_by_date: dict[date, float] = {}
    for w in weights_res.scalars().all():
        weight_by_date[w.measured_at.date()] = (
            w.trend_weight_kg if w.trend_weight_kg is not None else w.weight_kg
        )

    weight_dates = sorted(weight_by_date.keys())
    weight_trends = [weight_by_date[d] for d in weight_dates]

    # Current trailing 21-day window summary (ending on last_completed_day = ref_date - 1)
    latest_window_start = last_completed_day - timedelta(days=window_days - 1)
    lo_latest = bisect_left(valid_food_dates, latest_window_start)
    hi_latest = bisect_right(valid_food_dates, last_completed_day)
    latest_valid_kcals = valid_food_kcals[lo_latest:hi_latest]
    valid_nutrition_days_21d = len(latest_valid_kcals)
    avg_intake_21d = (
        round(sum(latest_valid_kcals) / valid_nutrition_days_21d, 1)
        if valid_nutrition_days_21d > 0
        else 0.0
    )

    w_lo_latest = bisect_left(weight_dates, latest_window_start)
    w_hi_latest = bisect_right(weight_dates, ref_date)
    weights_in_window_count = max(0, w_hi_latest - w_lo_latest)

    if weight_dates:
        if valid_nutrition_days_21d > 0:
            first_fd = valid_food_dates[lo_latest]
            start_ref = max(
                latest_window_start,
                first_fd - timedelta(days=1)
                if weight_dates[0] <= first_fd - timedelta(days=1)
                else weight_dates[0],
            )
        else:
            start_ref = max(latest_window_start, weight_dates[0])
        end_ref = min(ref_date, weight_dates[-1])
        start_trend_21d = _interpolate_trend(start_ref, weight_dates, weight_trends)
        end_trend_21d = _interpolate_trend(end_ref, weight_dates, weight_trends)
    else:
        start_trend_21d = 70.0
        end_trend_21d = 70.0

    daily_tdee: dict[date, float] = {}
    if base_tdee <= 0:
        if start_date is not None:
            cur = start_date
            while cur <= ref_date:
                daily_tdee[cur] = 0.0
                cur += timedelta(days=1)
        return DailyTdeeSeriesResult(
            daily_tdee=daily_tdee,
            latest_tdee_kcal=0.0,
            valid_nutrition_days_21d=valid_nutrition_days_21d,
            window_days=window_days,
            avg_intake_21d=avg_intake_21d,
            start_trend_weight_kg=round(start_trend_21d, 2),
            end_trend_weight_kg=round(end_trend_21d, 2),
            weights_in_window_count=weights_in_window_count,
        )

    sim_start_candidates: list[date] = [last_completed_day]
    if valid_food_dates:
        sim_start_candidates.append(valid_food_dates[0])
    if start_date is not None:
        sim_start_candidates.append(min(start_date, last_completed_day))
    sim_start = min(sim_start_candidates)

    est_tdee = float(base_tdee)
    cur_day = sim_start
    ramp_denom = float(
        max(1, CALIBRATED_NUTRITION_DAYS - MIN_NUTRITION_DAYS_FOR_ADAPTATION)
    )

    while cur_day <= last_completed_day:
        w_start = cur_day - timedelta(days=window_days - 1)
        f_lo = bisect_left(valid_food_dates, w_start)
        f_hi = bisect_right(valid_food_dates, cur_day)
        n_days = f_hi - f_lo

        if n_days >= MIN_NUTRITION_DAYS_FOR_ADAPTATION and len(weight_dates) >= 2:
            # Morning weigh-in on cur_day + 1 reflects the end of completed day cur_day.
            weight_cutoff = min(cur_day + timedelta(days=1), ref_date)
            w_hi = bisect_right(weight_dates, weight_cutoff)
            w_ext_lo = bisect_left(weight_dates, w_start - timedelta(days=7))
            w_in_win_lo = bisect_left(weight_dates, w_start)

            has_weight_coverage = (
                w_hi >= 2
                and (w_hi - w_ext_lo) >= 2
                and (w_hi - w_in_win_lo) >= 1
            )
            if has_weight_coverage:
                first_food_day = valid_food_dates[f_lo]
                earliest_w = weight_dates[0]
                latest_w = weight_dates[w_hi - 1]

                t0_candidate = first_food_day - timedelta(days=1)
                t0 = max(w_start, t0_candidate if earliest_w <= t0_candidate else earliest_w)
                t1 = min(weight_cutoff, latest_w)
                if (t1 - t0).days < 3:
                    t0 = max(w_start, earliest_w)

                days_span = (t1 - t0).days
                if days_span >= 3:
                    avg_in = sum(valid_food_kcals[f_lo:f_hi]) / float(n_days)
                    s_trend = _interpolate_trend(t0, weight_dates, weight_trends)
                    e_trend = _interpolate_trend(t1, weight_dates, weight_trends)
                    raw_tdee = avg_in - (
                        ((e_trend - s_trend) * KCAL_PER_KG) / float(days_span)
                    )
                    # Guard against extreme single-window outliers before smoothing.
                    raw_tdee = max(
                        max(1000.0, est_tdee - 1200.0),
                        min(est_tdee + 1200.0, raw_tdee),
                    )
                    progress = min(
                        1.0,
                        (n_days - MIN_NUTRITION_DAYS_FOR_ADAPTATION) / ramp_denom,
                    )
                    # Smooth startup at day 5 (25% ramp) -> full responsiveness at day 14 (100%).
                    ramp = 0.25 + 0.75 * progress
                    alpha = DAILY_TDEE_ALPHA * ramp
                    max_step = MIN_DAILY_TDEE_DELTA + (
                        MAX_DAILY_TDEE_DELTA - MIN_DAILY_TDEE_DELTA
                    ) * progress
                    step = max(-max_step, min(max_step, (raw_tdee - est_tdee) * alpha))
                    est_tdee = max(1000.0, est_tdee + step)

        daily_tdee[cur_day] = round(est_tdee, 0)
        cur_day += timedelta(days=1)

    latest_tdee = round(est_tdee, 0)
    # Carry yesterday's completed TDEE onto today (never use today's incomplete intake).
    daily_tdee[ref_date] = latest_tdee

    if start_date is not None and start_date < sim_start:
        fill_day = start_date
        while fill_day < sim_start:
            daily_tdee[fill_day] = round(base_tdee, 0)
            fill_day += timedelta(days=1)

    return DailyTdeeSeriesResult(
        daily_tdee=daily_tdee,
        latest_tdee_kcal=latest_tdee,
        valid_nutrition_days_21d=valid_nutrition_days_21d,
        window_days=window_days,
        avg_intake_21d=avg_intake_21d,
        start_trend_weight_kg=round(start_trend_21d, 2),
        end_trend_weight_kg=round(end_trend_21d, 2),
        weights_in_window_count=weights_in_window_count,
    )


async def refresh_profile_daily_tdee(
    db: AsyncSession,
    profile: UserProfile,
    *,
    commit: bool = False,
) -> float:
    """Recompute and sync ONLY profile.current_tdee_kcal without touching weekly targets."""
    if profile.initial_tdee_kcal <= 0 and profile.current_tdee_kcal <= 0:
        return 0.0
    series = await compute_daily_tdee_series(db, profile)
    if (
        series.latest_tdee_kcal > 0
        and round(profile.current_tdee_kcal, 0) != series.latest_tdee_kcal
    ):
        profile.current_tdee_kcal = series.latest_tdee_kcal
        if commit:
            await db.commit()
    return series.latest_tdee_kcal


async def compute_adaptive_checkin(
    db: AsyncSession,
    profile: UserProfile,
    reference_date: date | None = None,
    window_days: int = DEFAULT_WINDOW_DAYS,
) -> CheckinComputation:
    """Compute adaptive weekly check-in recommendations from the daily TDEE engine."""
    today = date.today()
    ref_date = min(reference_date, today) if reference_date is not None else today
    # Exclude today (incomplete) and any future dates: only completed past days (< today).
    period_end = ref_date - timedelta(days=1)
    period_start = period_end - timedelta(days=window_days - 1)

    series = await compute_daily_tdee_series(
        db,
        profile,
        end_date=ref_date,
        window_days=window_days,
    )

    last_checkin_res = await db.execute(
        select(WeeklyCheckin)
        .where(
            WeeklyCheckin.user_id == profile.user_id,
            WeeklyCheckin.accepted.is_(True),
            is_real_weekly_checkin_clause(),
        )
        .order_by(desc(WeeklyCheckin.checkin_date), desc(WeeklyCheckin.created_at))
        .limit(1)
    )
    last_checkin = last_checkin_res.scalar_one_or_none()
    last_checkin_date = last_checkin.checkin_date if last_checkin is not None else None

    if last_checkin is not None and last_checkin.calculated_tdee_kcal > 0:
        previous_tdee = round(last_checkin.calculated_tdee_kcal, 0)
    elif profile.initial_tdee_kcal > 0:
        previous_tdee = round(profile.initial_tdee_kcal, 0)
    else:
        previous_tdee = round(profile.current_tdee_kcal, 0)

    days_logged_count = series.valid_nutrition_days_21d
    calculated_tdee = series.latest_tdee_kcal

    if (
        days_logged_count < MIN_NUTRITION_DAYS_FOR_ADAPTATION
        or series.weights_in_window_count < 2
    ):
        confidence: Literal["low", "medium", "high"] = "low"
    elif days_logged_count >= CALIBRATED_NUTRITION_DAYS:
        confidence = "high"
    else:
        confidence = "medium"

    macros = calculate_macro_targets(
        profile, calculated_tdee, series.end_trend_weight_kg
    )

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
        avg_intake_kcal=series.avg_intake_21d,
        days_logged_count=days_logged_count,
        valid_nutrition_days_21d=days_logged_count,
        window_days=window_days,
        start_trend_weight_kg=series.start_trend_weight_kg,
        end_trend_weight_kg=series.end_trend_weight_kg,
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
