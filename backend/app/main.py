from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import app.models  # noqa: F401
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import Base, engine, get_db


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
