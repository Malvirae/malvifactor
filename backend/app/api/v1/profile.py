from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.tracking import WeeklyCheckin, WeightLog
from app.models.user import (
    Sex,
    User,
    UserProfile,
)
from app.schemas.profile import ProfileResponse, ProfileUpdate
from app.services.tdee_engine import calculate_macro_targets

router = APIRouter(prefix="/profile", tags=["profile"])

ACTIVITY_MULTIPLIERS: dict[str, float] = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "active": 1.725,
    "very_active": 1.9,
}

NEAT_BASE_MULTIPLIERS: dict[str, float] = {
    "sedentary_desk": 1.20,
    "lightly_active_daily": 1.30,
    "standing_active": 1.40,
    "very_mobile": 1.52,
}

WORKOUT_BONUS_PER_SESSION: dict[str, float] = {
    "strength": 0.035,
    "cardio": 0.050,
    "mixed": 0.042,
}


def _compute_age(birth_date: date) -> int:
    today = date.today()
    return (
        today.year
        - birth_date.year
        - ((today.month, today.day) < (birth_date.month, birth_date.day))
    )


def _calculate_initial_targets(
    profile: UserProfile,
    weight_kg: float,
    *,
    body_fat_pct: float | None = None,
    neat_level: str | None = None,
    workouts_per_week: int | None = None,
    workout_type: str | None = None,
    manual_initial_tdee_kcal: int | None = None,
) -> tuple[float, float, float, float, float]:
    """Compute initial TDEE (Katch-McArdle or Mifflin-St Jeor) and macro targets."""
    if manual_initial_tdee_kcal is not None and manual_initial_tdee_kcal > 0:
        tdee_kcal = float(manual_initial_tdee_kcal)
    else:
        if body_fat_pct is not None and 5.0 <= body_fat_pct <= 60.0:
            lbm = weight_kg * (1.0 - body_fat_pct / 100.0)
            bmr = 370.0 + 21.6 * lbm
        else:
            age = max(15, _compute_age(profile.birth_date))
            sex_offset = 5.0 if profile.sex == Sex.MALE else -161.0
            bmr = 10.0 * weight_kg + 6.25 * profile.height_cm - 5.0 * age + sex_offset

        if neat_level is not None or workouts_per_week is not None:
            neat_base = NEAT_BASE_MULTIPLIERS.get(
                neat_level or "lightly_active_daily", 1.30
            )
            bonus = WORKOUT_BONUS_PER_SESSION.get(
                workout_type or "mixed", 0.042
            )
            multiplier = neat_base + (workouts_per_week or 0) * bonus
        else:
            multiplier = ACTIVITY_MULTIPLIERS.get(profile.activity_level, 1.55)

        tdee_kcal = round(bmr * multiplier, 0)

    macros = calculate_macro_targets(profile, tdee_kcal, weight_kg)
    return (
        tdee_kcal,
        macros.calorie_target,
        macros.protein_g,
        macros.fat_g,
        macros.carbs_g,
    )


async def _get_or_create_profile(db: AsyncSession, user: User) -> UserProfile:
    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == user.id)
    )
    profile = result.scalar_one_or_none()
    if profile is None:
        profile = UserProfile(user_id=user.id)
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    return profile


@router.get("", response_model=ProfileResponse)
async def get_profile(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserProfile:
    """Retrieve the authenticated user's physiological profile and nutrition targets."""
    return await _get_or_create_profile(db, current_user)


@router.put("", response_model=ProfileResponse)
async def update_profile(
    payload: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserProfile:
    """Update physiological profile and optionally compute Mifflin-St Jeor TDEE & macros."""
    profile = await _get_or_create_profile(db, current_user)
    old_tdee = profile.current_tdee_kcal
    old_kcal = profile.current_calorie_target
    old_protein = profile.current_protein_g
    old_fat = profile.current_fat_g
    old_carbs = profile.current_carbs_g

    if payload.display_name is not None and payload.display_name.strip():
        current_user.display_name = payload.display_name.strip()

    update_data = payload.model_dump(
        exclude_unset=True,
        exclude={
            "recalculate_targets",
            "reference_weight_kg",
            "display_name",
            "weight_kg",
            "body_fat_pct",
            "neat_level",
            "workouts_per_week",
            "workout_type",
            "manual_initial_tdee_kcal",
        },
    )
    for field, value in update_data.items():
        setattr(profile, field, value)

    should_recalculate = (
        payload.recalculate_targets
        or payload.manual_initial_tdee_kcal is not None
        or payload.neat_level is not None
        or payload.workouts_per_week is not None
    )

    if should_recalculate:
        weight_kg = payload.weight_kg or payload.reference_weight_kg
        if weight_kg is None:
            latest_weight_result = await db.execute(
                select(WeightLog.weight_kg)
                .where(WeightLog.user_id == current_user.id)
                .order_by(desc(WeightLog.measured_at))
                .limit(1)
            )
            weight_kg = latest_weight_result.scalar_one_or_none()

        if weight_kg is None and payload.manual_initial_tdee_kcal is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    "reference_weight_kg is required to calculate initial TDEE "
                    "when no weight log exists"
                ),
            )

        tdee_kcal, calorie_target, protein_g, fat_g, carbs_g = (
            _calculate_initial_targets(
                profile,
                weight_kg or 70.0,
                body_fat_pct=payload.body_fat_pct,
                neat_level=payload.neat_level,
                workouts_per_week=payload.workouts_per_week,
                workout_type=payload.workout_type,
                manual_initial_tdee_kcal=payload.manual_initial_tdee_kcal,
            )
        )
        profile.initial_tdee_kcal = tdee_kcal
        profile.current_tdee_kcal = tdee_kcal
        profile.current_calorie_target = calorie_target
        profile.current_protein_g = protein_g
        profile.current_fat_g = fat_g
        profile.current_carbs_g = carbs_g

    macros_changed = (
        profile.current_calorie_target != old_kcal
        or profile.current_protein_g != old_protein
        or profile.current_fat_g != old_fat
        or profile.current_carbs_g != old_carbs
        or profile.current_tdee_kcal != old_tdee
    )
    if macros_changed:
        today = date.today()
        earlier_res = await db.execute(
            select(WeeklyCheckin.id)
            .where(
                WeeklyCheckin.user_id == current_user.id,
                WeeklyCheckin.accepted.is_(True),
                WeeklyCheckin.checkin_date < today,
            )
            .limit(1)
        )
        if earlier_res.scalar_one_or_none() is None:
            baseline_date = min(
                current_user.created_at.date(), today - timedelta(days=1)
            )
            db.add(
                WeeklyCheckin(
                    user_id=current_user.id,
                    checkin_date=baseline_date,
                    period_start=baseline_date,
                    period_end=baseline_date,
                    avg_intake_kcal=0.0,
                    days_logged_count=0,
                    start_trend_weight_kg=0.0,
                    end_trend_weight_kg=0.0,
                    calculated_tdee_kcal=old_tdee,
                    new_calorie_target=old_kcal,
                    new_protein_g=old_protein,
                    new_fat_g=old_fat,
                    new_carbs_g=old_carbs,
                    accepted=True,
                )
            )

        db.add(
            WeeklyCheckin(
                user_id=current_user.id,
                checkin_date=today,
                period_start=today,
                period_end=today,
                avg_intake_kcal=0.0,
                days_logged_count=0,
                start_trend_weight_kg=0.0,
                end_trend_weight_kg=0.0,
                calculated_tdee_kcal=profile.current_tdee_kcal,
                new_calorie_target=profile.current_calorie_target,
                new_protein_g=profile.current_protein_g,
                new_fat_g=profile.current_fat_g,
                new_carbs_g=profile.current_carbs_g,
                accepted=True,
            )
        )

    await db.commit()
    await db.refresh(profile)
    return profile
