from typing import Any

import httpx
from fastapi import HTTPException, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.food import Food, FoodSource

OPENFOODFACTS_API_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
USER_AGENT = "MalviFactor/1.0 (https://etixel.com)"


def _to_float(value: Any, default: float | None = 0.0) -> float | None:
    if value is None or value == "":
        return default
    try:
        parsed = float(str(value).replace(",", ".").strip())
        return max(0.0, parsed)
    except ValueError:
        return default


async def get_or_fetch_food_by_barcode(
    db: AsyncSession,
    barcode: str,
) -> Food:
    """Return cached Open Food Facts product or fetch, persist, and return it."""
    clean_barcode = barcode.strip().replace(" ", "")
    if not clean_barcode:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Code-barres invalide",
        )

    custom_result = await db.execute(
        select(Food)
        .where(
            Food.source == FoodSource.CUSTOM,
            Food.external_id == clean_barcode,
        )
        .order_by(desc(Food.created_at))
        .limit(1)
    )
    custom_food = custom_result.scalar_one_or_none()
    if custom_food is not None:
        return custom_food

    existing_result = await db.execute(
        select(Food).where(
            Food.source == FoodSource.OFF,
            Food.external_id == clean_barcode,
        )
    )
    cached_food = existing_result.scalar_one_or_none()
    if cached_food is not None:
        return cached_food

    url = OPENFOODFACTS_API_URL.format(barcode=clean_barcode)
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, headers={"User-Agent": USER_AGENT})
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Erreur lors de la communication avec Open Food Facts",
        ) from exc

    if response.status_code == status.HTTP_404_NOT_FOUND:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Produit introuvable sur Open Food Facts",
        )
    if response.status_code >= 400:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Réponse invalide d'Open Food Facts",
        )

    payload: dict[str, Any] = response.json()
    if payload.get("status") != 1 or not isinstance(payload.get("product"), dict):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Produit introuvable sur Open Food Facts",
        )

    product = payload["product"]
    name = (
        str(product.get("product_name_fr") or product.get("product_name") or "").strip()
        or f"Produit {clean_barcode}"
    )[:255]
    raw_brand = str(product.get("brands") or "").strip()
    brand = raw_brand[:255] if raw_brand else None

    serving_qty = _to_float(product.get("serving_quantity"), default=None)
    serving_size_g = serving_qty if serving_qty and serving_qty > 0 else 100.0
    raw_serving_label = str(product.get("serving_size") or "").strip()
    serving_label = raw_serving_label[:100] if raw_serving_label else None

    nutriments: dict[str, Any] = product.get("nutriments") or {}
    protein = _to_float(nutriments.get("proteins_100g"), default=0.0) or 0.0
    fat = _to_float(nutriments.get("fat_100g"), default=0.0) or 0.0
    carbs = _to_float(nutriments.get("carbohydrates_100g"), default=0.0) or 0.0
    fiber = _to_float(nutriments.get("fiber_100g"), default=0.0) or 0.0

    kcal = _to_float(nutriments.get("energy-kcal_100g"), default=None)
    if kcal is None:
        kcal = round(4.0 * protein + 4.0 * carbs + 9.0 * fat, 1)

    food = Food(
        source=FoodSource.OFF,
        external_id=clean_barcode,
        name=name,
        brand=brand,
        serving_size_g=serving_size_g,
        serving_label=serving_label,
        kcal_per_100g=kcal,
        protein_per_100g=protein,
        fat_per_100g=fat,
        carbs_per_100g=carbs,
        fiber_per_100g=fiber,
        created_by_user_id=None,
    )
    db.add(food)
    await db.commit()
    await db.refresh(food)
    return food
