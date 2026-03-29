from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from .library import MangaLibrary, MangaNotFoundError

RawArc = dict[str, object]
CHAPTER_BUCKET_SIZE = 25


TITLE_ALIASES: dict[str, str] = {
    "one piece": "one_piece",
    "attack on titan": "attack_on_titan",
    "shingeki no kyojin": "attack_on_titan",
    "demon slayer": "demon_slayer",
    "kimetsu no yaiba": "demon_slayer",
}


BUILTIN_ARCS: dict[str, list[RawArc]] = {
    "attack_on_titan": [
        {"id": "aot-fall-of-shiganshina", "name": "Fall of Shiganshina Arc", "start_chapter": 1, "end_chapter": 2, "order": 1},
        {"id": "aot-trost", "name": "Trost Arc", "start_chapter": 3, "end_chapter": 14, "order": 2},
        {"id": "aot-female-titan", "name": "Female Titan Arc", "start_chapter": 15, "end_chapter": 34, "order": 3},
        {"id": "aot-clash-of-the-titans", "name": "Clash of the Titans Arc", "start_chapter": 35, "end_chapter": 50, "order": 4},
        {"id": "aot-uprising", "name": "Uprising Arc", "start_chapter": 51, "end_chapter": 70, "order": 5},
        {"id": "aot-return-to-shiganshina", "name": "Return to Shiganshina Arc", "start_chapter": 71, "end_chapter": 90, "order": 6},
        {"id": "aot-marley", "name": "Marley Arc", "start_chapter": 91, "end_chapter": 106, "order": 7},
        {"id": "aot-war-for-paradis", "name": "War for Paradis Arc", "start_chapter": 107, "end_chapter": 139, "order": 8},
    ],
    "demon_slayer": [
        {"id": "ds-final-selection", "name": "Final Selection Arc", "start_chapter": 1, "end_chapter": 9, "order": 1},
        {"id": "ds-kidnappers-bog", "name": "Kidnapper's Bog Arc", "start_chapter": 10, "end_chapter": 13, "order": 2},
        {"id": "ds-asakusa", "name": "Asakusa Arc", "start_chapter": 14, "end_chapter": 19, "order": 3},
        {"id": "ds-tsuzumi-mansion", "name": "Tsuzumi Mansion Arc", "start_chapter": 20, "end_chapter": 27, "order": 4},
        {"id": "ds-natagumo-mountain", "name": "Natagumo Mountain Arc", "start_chapter": 28, "end_chapter": 44, "order": 5},
        {"id": "ds-rehabilitation-training", "name": "Rehabilitation Training Arc", "start_chapter": 45, "end_chapter": 53, "order": 6},
        {"id": "ds-mugen-train", "name": "Mugen Train Arc", "start_chapter": 54, "end_chapter": 66, "order": 7},
        {"id": "ds-entertainment-district", "name": "Entertainment District Arc", "start_chapter": 67, "end_chapter": 97, "order": 8},
        {"id": "ds-swordsmith-village", "name": "Swordsmith Village Arc", "start_chapter": 98, "end_chapter": 127, "order": 9},
        {"id": "ds-hashira-training", "name": "Hashira Training Arc", "start_chapter": 128, "end_chapter": 136, "order": 10},
        {"id": "ds-infinity-castle", "name": "Infinity Castle Arc", "start_chapter": 137, "end_chapter": 183, "order": 11},
        {"id": "ds-sunrise-countdown", "name": "Sunrise Countdown Arc", "start_chapter": 184, "end_chapter": 205, "order": 12},
    ],
    "one_piece": [
        {"id": "op-romance-dawn", "name": "Romance Dawn Arc", "start_chapter": 1, "end_chapter": 7, "order": 1},
        {"id": "op-orange-town", "name": "Orange Town Arc", "start_chapter": 8, "end_chapter": 21, "order": 2},
        {"id": "op-syrup-village", "name": "Syrup Village Arc", "start_chapter": 22, "end_chapter": 41, "order": 3},
        {"id": "op-baratie", "name": "Baratie Arc", "start_chapter": 42, "end_chapter": 68, "order": 4},
        {"id": "op-arlong-park", "name": "Arlong Park Arc", "start_chapter": 69, "end_chapter": 95, "order": 5},
        {"id": "op-loguetown", "name": "Loguetown Arc", "start_chapter": 96, "end_chapter": 100, "order": 6},
        {"id": "op-reverse-mountain", "name": "Reverse Mountain Arc", "start_chapter": 101, "end_chapter": 105, "order": 7},
        {"id": "op-whiskey-peak", "name": "Whiskey Peak Arc", "start_chapter": 106, "end_chapter": 114, "order": 8},
        {"id": "op-little-garden", "name": "Little Garden Arc", "start_chapter": 115, "end_chapter": 129, "order": 9},
        {"id": "op-drum-island", "name": "Drum Island Arc", "start_chapter": 130, "end_chapter": 154, "order": 10},
        {"id": "op-alabasta", "name": "Alabasta Arc", "start_chapter": 155, "end_chapter": 217, "order": 11},
        {"id": "op-jaya", "name": "Jaya Arc", "start_chapter": 218, "end_chapter": 236, "order": 12},
        {"id": "op-skypiea", "name": "Skypiea Arc", "start_chapter": 237, "end_chapter": 302, "order": 13},
        {"id": "op-long-ring-long-land", "name": "Long Ring Long Land Arc", "start_chapter": 303, "end_chapter": 321, "order": 14},
        {"id": "op-water-7", "name": "Water 7 Arc", "start_chapter": 322, "end_chapter": 374, "order": 15},
        {"id": "op-enies-lobby", "name": "Enies Lobby Arc", "start_chapter": 375, "end_chapter": 430, "order": 16},
        {"id": "op-post-enies-lobby", "name": "Post-Enies Lobby Arc", "start_chapter": 431, "end_chapter": 441, "order": 17},
        {"id": "op-thriller-bark", "name": "Thriller Bark Arc", "start_chapter": 442, "end_chapter": 489, "order": 18},
        {"id": "op-sabaody-archipelago", "name": "Sabaody Archipelago Arc", "start_chapter": 490, "end_chapter": 513, "order": 19},
        {"id": "op-amazon-lily", "name": "Amazon Lily Arc", "start_chapter": 514, "end_chapter": 524, "order": 20},
        {"id": "op-impel-down", "name": "Impel Down Arc", "start_chapter": 525, "end_chapter": 549, "order": 21},
        {"id": "op-marineford", "name": "Marineford Arc", "start_chapter": 550, "end_chapter": 580, "order": 22},
        {"id": "op-post-war", "name": "Post-War Arc", "start_chapter": 581, "end_chapter": 597, "order": 23},
        {"id": "op-return-to-sabaody", "name": "Return to Sabaody Arc", "start_chapter": 598, "end_chapter": 602, "order": 24},
        {"id": "op-fish-man-island", "name": "Fish-Man Island Arc", "start_chapter": 603, "end_chapter": 653, "order": 25},
        {"id": "op-punk-hazard", "name": "Punk Hazard Arc", "start_chapter": 654, "end_chapter": 699, "order": 26},
        {"id": "op-dressrosa", "name": "Dressrosa Arc", "start_chapter": 700, "end_chapter": 801, "order": 27},
        {"id": "op-zou", "name": "Zou Arc", "start_chapter": 802, "end_chapter": 824, "order": 28},
        {"id": "op-whole-cake-island", "name": "Whole Cake Island Arc", "start_chapter": 825, "end_chapter": 902, "order": 29},
        {"id": "op-reverie", "name": "Reverie Arc", "start_chapter": 903, "end_chapter": 908, "order": 30},
        {"id": "op-wano-country", "name": "Wano Country Arc", "start_chapter": 909, "end_chapter": 1057, "order": 31},
        {"id": "op-egghead", "name": "Egghead Arc", "start_chapter": 1058, "end_chapter": None, "order": 32},
    ],
}


class ArcCatalog:
    def __init__(self, library: MangaLibrary, cache_root: Path) -> None:
        self.library = library
        self.cache_root = cache_root.expanduser().resolve()

    def list_arcs(self, series_id: str, *, force_refresh: bool = False) -> list[dict]:
        series = self._series_by_id(series_id)
        return self._list_arcs_for_series(series, force_refresh=force_refresh)

    def _list_arcs_for_series(self, series: dict, *, force_refresh: bool = False) -> list[dict]:
        series_id = series["id"]

        # "Singles" does not represent a real named series.
        if series["relative_path"] == ".":
            return []

        volumes = self.library.list_volumes(series_id)
        signature = self._volumes_signature(volumes)

        cached = None if force_refresh else self._read_cache(series_id, signature)
        if cached is not None:
            return cached

        source_key = self._resolve_source_key(series["title"])
        if source_key:
            items = self._normalize_items(BUILTIN_ARCS[source_key])
            source_name = f"builtin:{source_key}"
        else:
            items = self._infer_items_from_volumes(series["title"], volumes)
            source_name = "inferred:chapter-buckets" if items else "none"

        self._write_cache(
            series_id=series_id,
            series_title=series["title"],
            source=source_name,
            series_signature=signature,
            items=items,
        )

        return items

    def sync_all_series(self, *, force_refresh: bool = False) -> dict:
        summary = {
            "series_total": 0,
            "created": 0,
            "refreshed": 0,
            "unchanged": 0,
            "errors": [],
        }

        for series in self.library.list_series():
            # Skip root-level "Singles" pseudo-series.
            if series.get("relative_path") == ".":
                continue

            series_id = series["id"]
            summary["series_total"] += 1

            cache_path = self._cache_path(series_id)
            before_mtime = cache_path.stat().st_mtime if cache_path.exists() else None

            try:
                self._list_arcs_for_series(series, force_refresh=force_refresh)
            except Exception as exc:  # noqa: BLE001
                summary["errors"].append({"series_id": series_id, "error": str(exc)})
                continue

            after_mtime = cache_path.stat().st_mtime if cache_path.exists() else None
            if before_mtime is None and after_mtime is not None:
                summary["created"] += 1
            elif before_mtime is not None and after_mtime is not None and after_mtime != before_mtime:
                summary["refreshed"] += 1
            else:
                summary["unchanged"] += 1

        return summary

    def _series_by_id(self, series_id: str) -> dict:
        for series in self.library.list_series():
            if series["id"] == series_id:
                return series
        raise MangaNotFoundError("Series not found")

    def _cache_path(self, series_id: str) -> Path:
        return self.cache_root / f"{series_id}.json"

    def _read_cache(self, series_id: str, signature: str) -> list[dict] | None:
        path = self._cache_path(series_id)
        if not path.is_file():
            return None

        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            return None

        items = raw.get("items")
        if not isinstance(items, list):
            return None

        cached_signature = raw.get("series_signature")
        if cached_signature and isinstance(cached_signature, str) and cached_signature != signature:
            return None

        return self._normalize_items(items)

    def _write_cache(
        self,
        series_id: str,
        series_title: str,
        source: str,
        series_signature: str,
        items: list[dict],
    ) -> None:
        self.cache_root.mkdir(parents=True, exist_ok=True)
        payload = {
            "series_id": series_id,
            "series_title": series_title,
            "source": source,
            "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "series_signature": series_signature,
            "items": items,
        }
        self._cache_path(series_id).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    def _infer_items_from_volumes(self, series_title: str, volumes: list[dict]) -> list[dict]:
        chapter_numbers: list[float] = []
        for volume in volumes:
            title = str(volume.get("title") or "")
            relative_path = str(volume.get("relative_path") or "")
            chapter = self._extract_chapter_number(title)
            if chapter is None:
                chapter = self._extract_chapter_number(relative_path)
            if chapter is not None:
                chapter_numbers.append(chapter)

        if not chapter_numbers:
            return []

        unique = sorted(set(chapter_numbers))
        if len(unique) < 3:
            return []

        min_chapter = min(unique)
        max_chapter = max(unique)

        bucket_start_to_values: dict[int, list[float]] = {}
        for chapter in unique:
            base = chapter if chapter > 0 else 1.0
            bucket_index = int((base - 1) // CHAPTER_BUCKET_SIZE)
            bucket_start = bucket_index * CHAPTER_BUCKET_SIZE + 1
            bucket_start_to_values.setdefault(bucket_start, []).append(chapter)

        series_slug = self._slug(series_title)
        items: list[dict] = []
        for order, bucket_start in enumerate(sorted(bucket_start_to_values.keys()), start=1):
            nominal_end = bucket_start + CHAPTER_BUCKET_SIZE - 1
            if nominal_end >= max_chapter:
                bucket_end = max_chapter
            else:
                bucket_end = float(nominal_end)

            start_value = float(bucket_start)
            if start_value < min_chapter:
                start_value = min_chapter

            start_label = self._format_number(start_value)
            end_label = self._format_number(bucket_end)
            items.append(
                {
                    "id": f"{series_slug}-chapters-{start_label}-to-{end_label}",
                    "name": f"Chapters {start_label}-{end_label}",
                    "start_chapter": start_value,
                    "end_chapter": bucket_end,
                    "order": order,
                }
            )

        return items

    @staticmethod
    def _extract_chapter_number(text: str) -> float | None:
        matches = re.findall(r"(\d+(?:\.\d+)?)", text)
        if not matches:
            return None

        # Use the last numeric token to support names like "Vol 01 Ch 005".
        candidate = matches[-1]
        try:
            return float(candidate)
        except ValueError:
            return None

    @staticmethod
    def _format_number(value: float) -> str:
        if float(value).is_integer():
            return str(int(value))
        return str(value).rstrip("0").rstrip(".")

    @staticmethod
    def _volumes_signature(volumes: list[dict]) -> str:
        parts = [str(v.get("relative_path") or v.get("title") or "") for v in volumes]
        payload = "\n".join(sorted(parts)).encode("utf-8")
        return hashlib.sha1(payload).hexdigest()

    @staticmethod
    def _normalize_items(items: list[object]) -> list[dict]:
        normalized: list[dict] = []
        for idx, raw in enumerate(items, start=1):
            if not isinstance(raw, dict):
                continue

            name = raw.get("name")
            if not isinstance(name, str) or not name.strip():
                continue

            arc_id = raw.get("id")
            if not isinstance(arc_id, str) or not arc_id.strip():
                arc_id = ArcCatalog._slug(name)

            start = ArcCatalog._coerce_number(raw.get("start_chapter"))
            end = ArcCatalog._coerce_number(raw.get("end_chapter"))
            order = ArcCatalog._coerce_int(raw.get("order"))
            if order is None:
                order = idx

            normalized.append(
                {
                    "id": arc_id,
                    "name": name.strip(),
                    "start_chapter": start,
                    "end_chapter": end,
                    "order": order,
                }
            )

        normalized.sort(key=lambda item: item["order"] if item["order"] is not None else 10**9)
        return normalized

    @staticmethod
    def _coerce_number(value: object) -> float | None:
        if value is None:
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return float(text)
            except ValueError:
                return None
        return None

    @staticmethod
    def _coerce_int(value: object) -> int | None:
        if value is None:
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return int(float(text))
            except ValueError:
                return None
        return None

    @staticmethod
    def _slug(text: str) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        return slug or "arc"

    @staticmethod
    def _resolve_source_key(title: str) -> str | None:
        cleaned = re.sub(r"\s*\((en|english)\)\s*$", "", title, flags=re.IGNORECASE).strip().lower()
        return TITLE_ALIASES.get(cleaned)
