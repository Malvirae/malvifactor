from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

import app.models  # noqa: F401
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import AsyncSessionLocal, Base, engine, get_db
from app.models.tracking import TargetHistory, WeeklyCheckin
from app.models.user import User, UserProfile


async def _backfill_target_history() -> None:
    """Idempotently backfill versioned target_history for existing users."""
    async with AsyncSessionLocal() as session:
        existing_users_res = await session.execute(
            select(TargetHistory.user_id).distinct()
        )
        users_with_history = set(existing_users_res.scalars().all())

        profiles_res = await session.execute(
            select(UserProfile, User).join(User, User.id == UserProfile.user_id)
        )
        inserted_any = False

        for profile, user in profiles_res.all():
            if profile.user_id in users_with_history:
                continue

            checkins_res = await session.execute(
                select(WeeklyCheckin)
                .where(
                    WeeklyCheckin.user_id == profile.user_id,
                    WeeklyCheckin.accepted.is_(True),
                )
                .order_by(
                    WeeklyCheckin.checkin_date.asc(),
                    WeeklyCheckin.created_at.asc(),
                )
            )
            by_date: dict = {}
            for chk in checkins_res.scalars().all():
                if chk.new_calorie_target > 0:
                    by_date[chk.checkin_date] = chk

            if by_date:
                for effective_date, chk in sorted(by_date.items()):
                    is_legacy_manual = (
                        chk.period_start == chk.checkin_date
                        and chk.period_end == chk.checkin_date
                        and chk.days_logged_count == 0
                    )
                    session.add(
                        TargetHistory(
                            user_id=profile.user_id,
                            effective_from=effective_date,
                            target_kcal=chk.new_calorie_target,
                            target_protein_g=chk.new_protein_g,
                            target_fat_g=chk.new_fat_g,
                            target_carbs_g=chk.new_carbs_g,
                            source="manual" if is_legacy_manual else "checkin",
                        )
                    )
                inserted_any = True
            elif profile.current_calorie_target > 0:
                session.add(
                    TargetHistory(
                        user_id=profile.user_id,
                        effective_from=user.created_at.date(),
                        target_kcal=profile.current_calorie_target,
                        target_protein_g=profile.current_protein_g,
                        target_fat_g=profile.current_fat_g,
                        target_carbs_g=profile.current_carbs_g,
                        source="initial",
                    )
                )
                inserted_any = True

        if inserted_any:
            await session.commit()


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Create database tables, pg_trgm extension, and indexes on startup."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(
            text(
                "ALTER TABLE user_profiles "
                "ADD COLUMN IF NOT EXISTS target_weight_kg DOUBLE PRECISION;"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE user_profiles "
                "ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE;"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE foods "
                "ADD COLUMN IF NOT EXISTS stores VARCHAR(255);"
            )
        )
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS pg_trgm;"))
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS unaccent;"))
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_foods_name_trgm "
                "ON foods USING gin (name gin_trgm_ops);"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_foods_brand_trgm "
                "ON foods USING gin (brand gin_trgm_ops);"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_food_logs_user_logged_date "
                "ON food_logs (user_id, logged_date);"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_food_logs_user_logged_desc "
                "ON food_logs (user_id, logged_date DESC, logged_time DESC, created_at DESC);"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_weight_logs_user_measured_at "
                "ON weight_logs (user_id, measured_at DESC);"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_foods_custom_user_barcode "
                "ON foods (created_by_user_id, external_id) "
                "WHERE source = 'custom';"
            )
        )
        await conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS idx_target_history_user_effective_desc "
                "ON target_history (user_id, effective_from DESC, created_at DESC);"
            )
        )
    await _backfill_target_history()
    yield
    await engine.dispose()


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    lifespan=lifespan,
    docs_url="/docs",
    openapi_url="/openapi.json",
)

app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)


@app.get("/api/health", tags=["health"])
async def health_check(db: AsyncSession = Depends(get_db)) -> dict[str, str]:
    """Verify API and PostgreSQL database connectivity."""
    try:
        await db.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database connection failed",
        ) from exc
    return {"status": "ok", "database": "connected"}
