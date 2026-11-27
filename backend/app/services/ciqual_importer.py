import csv
import io
import math
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from openpyxl import load_workbook
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.food import Food, FoodSource

RECHERCHE_DATA_GOUV_DATASET_URL = (
    "https://entrepot.recherche.data.gouv.fr/api/datasets/:persistentId/"
    "?persistentId=doi:10.57745/RDMHWY"
)
RECHERCHE_DATA_GOUV_DATAFILE_URL = (
    "https://entrepot.recherche.data.gouv.fr/api/access/datafile/"
    "{file_id}?format=original"
)


@dataclass(slots=True)
class CiqualImportStats:
    """Summary counters for a Ciqual import run."""

    created: int = 0
    updated: int = 0
    skipped: int = 0


def _normalize_header(text_value: Any) -> str:
    if text_value is None:
        return ""
    raw = str(text_value).strip().lower()
    normalized = unicodedata.normalize("NFKD", raw)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch))


def _clean_nutrient_value(raw: Any) -> float:
    """Parse French Ciqual nutrient values (commas, '< 0,5', '-', 'traces')."""
    if raw is None:
        return 0.0
    if isinstance(raw, (int, float)):
        val = float(raw)
        return 0.0 if math.isnan(val) or val < 0.0 else val

    cleaned = str(raw).strip().lower()
    if not cleaned or cleaned in {"-", "traces", "trace", "tr", "nd", "n/a"}:
        return 0.0

    cleaned = cleaned.replace("\xa0", "").replace(" ", "").replace(",", ".")
    if cleaned.startswith("<"):
        try:
            upper = float(cleaned[1:])
            return max(0.0, round(upper / 2.0, 4))
        except ValueError:
            return 0.0

    try:
        return max(0.0, float(cleaned))
    except ValueError:
        return 0.0


def _detect_columns(headers: list[Any]) -> dict[str, int]:
    """Dynamically map required Ciqual columns by keyword matching."""
    norm_headers = [_normalize_header(h) for h in headers]
    mapping: dict[str, int] = {}

    for idx, h in enumerate(norm_headers):
        if "alim_code" in h and "code" not in mapping:
            mapping["code"] = idx
        elif "alim_nom_fr" in h and "name" not in mapping:
            mapping["name"] = idx
        elif (
            "energie" in h
            and "1169/2011" in h
            and "kcal" in h
            and "kcal" not in mapping
        ):
            mapping["kcal"] = idx
        elif "proteines" in h and "jones" in h and "protein" not in mapping:
            mapping["protein"] = idx
        elif "lipides" in h and ("g/100" in h or h.startswith("lipides")) and "fat" not in mapping:
            mapping["fat"] = idx
        elif "glucides" in h and ("g/100" in h or h.startswith("glucides")) and "carbs" not in mapping:
            mapping["carbs"] = idx
        elif "fibres" in h and "alimentaires" in h and "fiber" not in mapping:
            mapping["fiber"] = idx

    # Fallbacks for slight naming differences across Ciqual editions
    for idx, h in enumerate(norm_headers):
        if "kcal" not in mapping and "energie" in h and "kcal" in h:
            mapping["kcal"] = idx
        if "protein" not in mapping and "proteines" in h:
            mapping["protein"] = idx
        if "fat" not in mapping and "lipides" in h:
            mapping["fat"] = idx
        if "carbs" not in mapping and "glucides" in h:
            mapping["carbs"] = idx
        if "fiber" not in mapping and "fibres" in h:
            mapping["fiber"] = idx

    required = {"code", "name", "kcal", "protein", "fat", "carbs"}
    missing = required - set(mapping.keys())
    if missing:
        raise ValueError(
            f"Colonnes Ciqual introuvables dans l'en-tête : {sorted(missing)}"
        )
    return mapping


def _parse_xlsx_rows(content: bytes) -> tuple[dict[str, int], list[tuple[Any, ...]]]:
    wb = load_workbook(io.BytesIO(content), read_only=True, data_only=True)
    try:
        ws = wb.active
        rows_iter = ws.iter_rows(values_only=True)
        headers = next(rows_iter, None)
        if not headers:
            raise ValueError("Fichier XLSX Ciqual vide.")
        col_map = _detect_columns(list(headers))
        rows = list(rows_iter)
        return col_map, rows
    finally:
        wb.close()


def _parse_csv_rows(content: bytes) -> tuple[dict[str, int], list[tuple[Any, ...]]]:
    text_data: str | None = None
    for encoding in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            text_data = content.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    if text_data is None:
        raise ValueError("Impossible de décoder le fichier CSV Ciqual.")

    sample = text_data[:4096]
    delimiter = ";" if sample.count(";") >= sample.count(",") else ","
    reader = csv.reader(io.StringIO(text_data), delimiter=delimiter)
    headers = next(reader, None)
    if not headers:
        raise ValueError("Fichier CSV Ciqual vide.")
    col_map = _detect_columns(headers)
    rows = [tuple(row) for row in reader]
    return col_map, rows


async def _fetch_latest_ciqual_resource() -> tuple[str, bytes]:
    """Fetch the official French Ciqual 2025 .xlsx file from Recherche Data Gouv."""
    headers = {"User-Agent": "MalviFactor/1.0 (https://etixel.com)"}
    async with httpx.AsyncClient(timeout=120.0, follow_redirects=True) as client:
        resp = await client.get(RECHERCHE_DATA_GOUV_DATASET_URL, headers=headers)
        resp.raise_for_status()
        payload = resp.json()

        files: list[dict[str, Any]] = (
            payload.get("data", {})
            .get("latestVersion", {})
            .get("files", [])
        )

        selected_file_id: int | str | None = None
        for item in files:
            data_file = item.get("dataFile") or {}
            filename = str(
                data_file.get("filename") or item.get("label") or ""
            ).strip()
            lower_name = filename.lower()

            if not lower_name.endswith(".xlsx"):
                continue
            if "eng" in lower_name or "english" in lower_name:
                continue

            file_id = data_file.get("id")
            if file_id is not None:
                selected_file_id = file_id
                break

        if selected_file_id is None:
            raise ValueError(
                "Fichier Ciqual français (.xlsx) introuvable dans le dataset Recherche Data Gouv"
            )

        download_url = RECHERCHE_DATA_GOUV_DATAFILE_URL.format(
            file_id=selected_file_id
        )
        file_resp = await client.get(download_url, headers=headers)
        file_resp.raise_for_status()
        return ".xlsx", file_resp.content


async def import_ciqual(
    db: AsyncSession,
    file_path: str | Path | None = None,
) -> CiqualImportStats:
    """Import or update official Ciqual ANSES foods idempotently."""
    if file_path is not None:
        path = Path(file_path)
        if not path.is_file():
            raise FileNotFoundError(f"Fichier introuvable : {path}")
        content = path.read_bytes()
        ext = path.suffix.lower()
    else:
        ext, content = await _fetch_latest_ciqual_resource()

    if ext == ".csv":
        col_map, rows = _parse_csv_rows(content)
    else:
        col_map, rows = _parse_xlsx_rows(content)

    existing_result = await db.execute(
        select(Food).where(Food.source == FoodSource.CIQUAL)
    )
    existing_by_code: dict[str, Food] = {
        food.external_id: food
        for food in existing_result.scalars().all()
        if food.external_id is not None
    }

    stats = CiqualImportStats()
    fiber_idx = col_map.get("fiber")

    for row in rows:
        if len(row) <= max(col_map.values()):
            stats.skipped += 1
            continue

        raw_code = row[col_map["code"]]
        raw_name = row[col_map["name"]]
        if raw_code is None or raw_name is None:
            stats.skipped += 1
            continue

        alim_code = str(raw_code).strip()
        if alim_code.endswith(".0"):
            alim_code = alim_code[:-2]
        name = str(raw_name).strip()[:255]
        if not alim_code or not name:
            stats.skipped += 1
            continue

        kcal = _clean_nutrient_value(row[col_map["kcal"]])
        protein = _clean_nutrient_value(row[col_map["protein"]])
        fat = _clean_nutrient_value(row[col_map["fat"]])
        carbs = _clean_nutrient_value(row[col_map["carbs"]])
        fiber = _clean_nutrient_value(row[fiber_idx]) if fiber_idx is not None else 0.0

        existing_food = existing_by_code.get(alim_code)
        if existing_food is not None:
            existing_food.name = name
            existing_food.serving_size_g = 100.0
            existing_food.kcal_per_100g = kcal
            existing_food.protein_per_100g = protein
            existing_food.fat_per_100g = fat
            existing_food.carbs_per_100g = carbs
            existing_food.fiber_per_100g = fiber
            stats.updated += 1
        else:
            new_food = Food(
                source=FoodSource.CIQUAL,
                external_id=alim_code,
                name=name,
                brand=None,
                serving_size_g=100.0,
                serving_label=None,
                kcal_per_100g=kcal,
                protein_per_100g=protein,
                fat_per_100g=fat,
                carbs_per_100g=carbs,
                fiber_per_100g=fiber,
                created_by_user_id=None,
            )
            db.add(new_food)
            existing_by_code[alim_code] = new_food
            stats.created += 1

    await db.commit()
    return stats
