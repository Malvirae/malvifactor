from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.tracking import WeightSource


class WeightCreate(BaseModel):
    """Create a manual weight measurement."""

    measured_at: datetime
    weight_kg: float = Field(..., gt=20.0, lt=350.0)
    body_fat_pct: float | None = Field(default=None, ge=1.0, le=70.0)


class WeightSyncItem(BaseModel):
    """Single Health Connect weight record."""

    measured_at: datetime
    weight_kg: float = Field(..., gt=20.0, lt=350.0)
    body_fat_pct: float | None = Field(default=None, ge=1.0, le=70.0)


class WeightSyncRequest(BaseModel):
    """Batch Health Connect weight sync payload."""

    items: list[WeightSyncItem] = Field(..., min_length=1)


class WeightResponse(BaseModel):
    """Serialized weight measurement with EWMA trend."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    measured_at: datetime
    weight_kg: float
    body_fat_pct: float | None
    trend_weight_kg: float | None
    source: WeightSource


class WeightSyncResponse(BaseModel):
    """Summary returned after a Health Connect batch sync."""

    synced_count: int
    latest_weight_kg: float | None
    latest_trend_weight_kg: float | None
