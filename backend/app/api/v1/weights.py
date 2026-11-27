from datetime import date, datetime, time
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.tracking import WeightLog, WeightSource
from app.models.user import User
from app.schemas.weights import (
    WeightCreate,
    WeightResponse,
    WeightSyncRequest,
    WeightSyncResponse,
)
from app.services.tdee_engine import recalculate_weight_trends

router = APIRouter(prefix="/weights", tags=["weights"])


@router.get("", response_model=list[WeightResponse])
async def list_weights(
    start_date: date | None = Query(default=None),
    end_date: date | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[WeightLog]:
    """Return chronological weight history with EWMA trend (up to today)."""
    today = date.today()
    effective_end = min(end_date, today) if end_date is not None else today
    stmt = select(WeightLog).where(WeightLog.user_id == current_user.id)
    if start_date is not None:
        start_dt = datetime.combine(start_date, time.min).astimezone()
        stmt = stmt.where(WeightLog.measured_at >= start_dt)
    end_dt = datetime.combine(effective_end, time.max).astimezone()
    stmt = stmt.where(WeightLog.measured_at <= end_dt)

    stmt = stmt.order_by(WeightLog.measured_at.asc())
    res = await db.execute(stmt)
    return list(res.scalars().all())


@router.post("", response_model=WeightResponse, status_code=status.HTTP_201_CREATED)
async def create_manual_weight(
    payload: WeightCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WeightLog:
    """Create or update a manual weight log and recalculate EWMA trends."""
    existing_res = await db.execute(
        select(WeightLog).where(
            WeightLog.user_id == current_user.id,
            WeightLog.measured_at == payload.measured_at,
        )
    )
    weight_log = existing_res.scalar_one_or_none()
    if weight_log is not None:
        weight_log.weight_kg = payload.weight_kg
        weight_log.body_fat_pct = payload.body_fat_pct
        weight_log.source = WeightSource.MANUAL
    else:
        weight_log = WeightLog(
            user_id=current_user.id,
            measured_at=payload.measured_at,
            weight_kg=payload.weight_kg,
            body_fat_pct=payload.body_fat_pct,
            source=WeightSource.MANUAL,
        )
        db.add(weight_log)

    await db.flush()
    await recalculate_weight_trends(db, current_user.id)
    await db.refresh(weight_log)
    return weight_log


@router.post("/sync", response_model=WeightSyncResponse)
async def sync_health_connect_weights(
    payload: WeightSyncRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WeightSyncResponse:
    """Idempotent batch upsert of Health Connect weight records."""
    timestamps = [item.measured_at for item in payload.items]
    existing_res = await db.execute(
        select(WeightLog).where(
            WeightLog.user_id == current_user.id,
            WeightLog.measured_at.in_(timestamps),
        )
    )
    existing_by_ts = {
        row.measured_at: row for row in existing_res.scalars().all()
    }

    for item in payload.items:
        existing = existing_by_ts.get(item.measured_at)
        if existing is not None:
            existing.weight_kg = item.weight_kg
            existing.body_fat_pct = item.body_fat_pct
            existing.source = WeightSource.HEALTH_CONNECT
        else:
            new_row = WeightLog(
                user_id=current_user.id,
                measured_at=item.measured_at,
                weight_kg=item.weight_kg,
                body_fat_pct=item.body_fat_pct,
                source=WeightSource.HEALTH_CONNECT,
            )
            db.add(new_row)
            existing_by_ts[item.measured_at] = new_row

    await db.flush()
    logs = await recalculate_weight_trends(db, current_user.id)
    latest = logs[-1] if logs else None
    return WeightSyncResponse(
        synced_count=len(payload.items),
        latest_weight_kg=latest.weight_kg if latest else None,
        latest_trend_weight_kg=latest.trend_weight_kg if latest else None,
    )


@router.delete("/{weight_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_weight(
    weight_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Delete a weight measurement and recalculate EWMA trends."""
    res = await db.execute(select(WeightLog).where(WeightLog.id == weight_id))
    weight_log = res.scalar_one_or_none()
    if weight_log is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Pesée introuvable",
        )
    if weight_log.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès refusé à cette pesée",
        )

    await db.delete(weight_log)
    await db.flush()
    await recalculate_weight_trends(db, current_user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
