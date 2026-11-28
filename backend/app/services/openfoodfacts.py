import re
import unicodedata
from typing import Any

import httpx
from fastapi import HTTPException, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.food import Food, FoodSource

OPENFOODFACTS_API_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OPENFOODFACTS_SEARCH_URL = "https://fr.openfoodfacts.org/cgi/search.pl"
USER_AGENT = "MalviFactor/1.2 (https://etixel.com)"

_STOP_WORDS = {"de", "du", "des", "au", "aux", "et", "en", "a", "l", "d"}


def normalize_search_text(value: str | None) -> str:
    """Lowercase, strip accents, and normalize whitespace for search matching."""
    if not value:
        return ""
    raw = str(value).strip().lower()
    decomposed = unicodedata.normalize("NFKD", raw)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", stripped).strip()


def tokenize_search_query(query: str) -> list[str]:
    """Split normalized query into meaningful tokens, preserving short brand tokens like 'le' or 'u'."""
    norm = normalize_search_text(query)
    if not norm:
        return []
    raw_tokens = [t for t in re.split(r"[\s,;'\"’\-/]+", norm) if t]
    if not raw_tokens:
        return []
    filtered = [t for t in raw_tokens if t not in _STOP_WORDS]
    return filtered if filtered else raw_tokens


def _to_float(value: Any, default: float | None = 0.0) -> float | None:
    if value is None or value == "":
        return default
    try:
        parsed = float(str(value).replace(",", ".").strip())
        return max(0.0, parsed)
    except ValueError:
        return default


def _extract_nutrition(nutriments: dict[str, Any]) -> tuple[float, float, float, float, float] | None:
    protein = _to_float(nutriments.get("proteins_100g"), default=None)
    fat = _to_float(nutriments.get("fat_100g"), default=None)
    carbs = _to_float(nutriments.get("carbohydrates_100g"), default=None)
    fiber = _to_float(nutriments.get("fiber_100g"), default=0.0) or 0.0
    kcal = _to_float(nutriments.get("energy-kcal_100g"), default=None)

    has_any = any(v is not None for v in (kcal, protein, fat, carbs))
    if not has_any:
        return None

    p_val = protein or 0.0
    f_val = fat or 0.0
    c_val = carbs or 0.0
    if kcal is None:
        kcal = round(4.0 * p_val + 4.0 * c_val + 9.0 * f_val, 1)

    return kcal, p_val, f_val, c_val, fiber


def _clean_comma_list(raw: Any, max_len: int = 255) -> str | None:
    if not raw:
        return None
    parts = [p.strip() for p in str(raw).split(",") if p.strip()]
    if not parts:
        return None
    joined = ", ".join(dict.fromkeys(parts))
    return joined[:max_len]


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
    brand = _clean_comma_list(product.get("brands"))
    stores = _clean_comma_list(product.get("stores"))

    serving_qty = _to_float(product.get("serving_quantity"), default=None)
    serving_size_g = serving_qty if serving_qty and serving_qty > 0 else 100.0
    raw_serving_label = str(product.get("serving_size") or "").strip()
    serving_label = raw_serving_label[:100] if raw_serving_label else None

    nutriments: dict[str, Any] = product.get("nutriments") or {}
    parsed = _extract_nutrition(nutriments)
    if parsed is not None:
        kcal, protein, fat, carbs, fiber = parsed
    else:
        kcal, protein, fat, carbs, fiber = 0.0, 0.0, 0.0, 0.0, 0.0

    food = Food(
        source=FoodSource.OFF,
        external_id=clean_barcode,
        name=name,
        brand=brand,
        stores=stores,
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


async def search_openfoodfacts_products(
    db: AsyncSession,
    query: str,
    tokens: list[str],
    limit: int = 20,
) -> list[Food]:
    """Query French OpenFoodFacts full-text search, score matches, and cache valid products."""
    if not query.strip() or not tokens:
        return []

    params = {
        "search_terms": query.strip(),
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "lc": "fr",
        "cc": "fr",
        "page_size": 25,
        "fields": (
            "code,product_name,product_name_fr,brands,stores,"
            "nutriments,serving_size,serving_quantity,categories_tags"
        ),
    }

    try:
        async with httpx.AsyncClient(timeout=4.5) as client:
            response = await client.get(
                OPENFOODFACTS_SEARCH_URL,
                params=params,
                headers={"User-Agent": USER_AGENT},
            )
        if response.status_code >= 400:
            return []
        payload = response.json()
    except Exception:
        return []

    products = payload.get("products")
    if not isinstance(products, list) or not products:
        return []

    norm_query = normalize_search_text(query)
    scored_candidates: list[tuple[float, dict[str, Any]]] = []

    for prod in products:
        if not isinstance(prod, dict):
            continue
        code = str(prod.get("code") or "").strip()
        raw_name = str(
            prod.get("product_name_fr") or prod.get("product_name") or ""
        ).strip()
        if not code or not raw_name:
            continue

        nutriments = prod.get("nutriments")
        if not isinstance(nutriments, dict):
            continue
        parsed_macros = _extract_nutrition(nutriments)
        if parsed_macros is None:
            continue

        brand_str = _clean_comma_list(prod.get("brands")) or ""
        stores_str = _clean_comma_list(prod.get("stores")) or ""
        norm_name = normalize_search_text(raw_name)
        norm_brand = normalize_search_text(brand_str)
        norm_stores = normalize_search_text(stores_str)
        combined = f"{norm_name} {norm_brand} {norm_stores}".strip()

        matched_tokens = sum(1 for t in tokens if t in combined)
        if matched_tokens == 0:
            continue

        score = float(matched_tokens * 20)
        if matched_tokens == len(tokens):
            score += 45.0
        if norm_name == norm_query:
            score += 80.0
        elif norm_name.startswith(norm_query):
            score += 40.0
        if any(t in norm_brand for t in tokens):
            score += 15.0
        if any(t in norm_stores for t in tokens):
            score += 15.0

        scored_candidates.append(
            (
                score,
                {
                    "code": code,
                    "name": raw_name[:255],
                    "brand": brand_str[:255] if brand_str else None,
                    "stores": stores_str[:255] if stores_str else None,
                    "serving_qty": _to_float(prod.get("serving_quantity"), default=None),
                    "serving_label": str(prod.get("serving_size") or "").strip()[:100]
                    or None,
                    "macros": parsed_macros,
                },
            )
        )

    if not scored_candidates:
        return []

    scored_candidates.sort(key=lambda pair: pair[0], reverse=True)
    top_items = [item for _, item in scored_candidates[:limit]]

    codes = [item["code"] for item in top_items]
    existing_res = await db.execute(
        select(Food).where(
            Food.source == FoodSource.OFF,
            Food.external_id.in_(codes),
        )
    )
    existing_by_code = {
        f.external_id: f for f in existing_res.scalars().all() if f.external_id
    }

    persisted: list[Food] = []
    added_or_updated = False

    for item in top_items:
        code = item["code"]
        existing = existing_by_code.get(code)
        if existing is not None:
            if not existing.stores and item["stores"]:
                existing.stores = item["stores"]
                added_or_updated = True
            if not existing.brand and item["brand"]:
                existing.brand = item["brand"]
                added_or_updated = True
            persisted.append(existing)
            continue

        kcal, protein, fat, carbs, fiber = item["macros"]
        serving_qty = item["serving_qty"]
        serving_size_g = serving_qty if serving_qty and serving_qty > 0 else 100.0
        food = Food(
            source=FoodSource.OFF,
            external_id=code,
            name=item["name"],
            brand=item["brand"],
            stores=item["stores"],
            serving_size_g=serving_size_g,
            serving_label=item["serving_label"],
            kcal_per_100g=kcal,
            protein_per_100g=protein,
            fat_per_100g=fat,
            carbs_per_100g=carbs,
            fiber_per_100g=fiber,
            created_by_user_id=None,
        )
        db.add(food)
        existing_by_code[code] = food
        persisted.append(food)
        added_or_updated = True

    if added_or_updated:
        try:
            await db.commit()
            for food in persisted:
                await db.refresh(food)
        except Exception:
            await db.rollback()
            return [f for f in persisted if f.id is not None]

    return persisted
