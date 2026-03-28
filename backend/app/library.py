from __future__ import annotations

import base64
import mimetypes
import re
import zipfile
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}
ARCHIVE_EXTENSIONS = {".cbz", ".zip"}
VIDEO_EXTENSIONS = {".mkv", ".mp4", ".mov", ".avi", ".m4v", ".wmv", ".webm", ".ts"}
MIN_IMAGE_FILES_PER_VOLUME = 3
COVER_BASENAMES = ("cover", "folder", "poster")


class MangaLibraryError(Exception):
    pass


class MangaNotFoundError(MangaLibraryError):
    pass


class MangaBadRequestError(MangaLibraryError):
    pass


def natural_sort_key(value: str) -> list[object]:
    parts = re.split(r"(\d+)", value)
    return [int(part) if part.isdigit() else part.lower() for part in parts]


class MangaLibrary:
    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()
        self._archive_page_cache: dict[str, list[str]] = {}
        self._directory_page_cache: dict[str, list[Path]] = {}
        self._volume_kind_cache: dict[str, str | None] = {}

    def list_series(self) -> list[dict]:
        if not self.root.exists() or not self.root.is_dir():
            return []

        series: list[dict] = []
        root_level_volumes = self._list_root_level_volumes()

        for entry in self._sorted_entries(self.root):
            if not entry.is_dir():
                continue

            volumes = self._find_volumes_in_directory(entry)
            if not volumes:
                continue

            relative_path = entry.relative_to(self.root).as_posix()
            series.append(
                {
                    "id": self._encode_relative_path(relative_path),
                    "title": entry.name,
                    "relative_path": relative_path,
                    "volume_count": len(volumes),
                    "cover_url": self._series_cover_url(relative_path),
                }
            )

        if root_level_volumes:
            series.insert(
                0,
                {
                    "id": self._encode_relative_path("."),
                    "title": "Singles",
                    "relative_path": ".",
                    "volume_count": len(root_level_volumes),
                    "cover_url": None,
                },
            )

        return series

    def list_volumes(self, series_id: str) -> list[dict]:
        series_path = self._resolve_id_to_path(series_id)

        if series_path == self.root:
            entries = self._list_root_level_volumes()
            return [self._volume_payload(entry, series_id) for entry in entries]

        if not series_path.exists() or not series_path.is_dir():
            raise MangaNotFoundError("Series not found")

        entries = self._find_volumes_in_directory(series_path)
        return [self._volume_payload(entry, series_id) for entry in entries]

    def list_pages(self, volume_id: str) -> list[dict]:
        volume_path = self._resolve_id_to_path(volume_id)
        kind = self._volume_kind(volume_path)

        if kind == "archive":
            pages = self._archive_pages(volume_path)
        elif kind == "directory":
            pages = [p.relative_to(volume_path).as_posix() for p in self._directory_pages(volume_path)]
        else:
            raise MangaNotFoundError("Volume not found")

        return [
            {
                "index": idx,
                "name": name,
                "url": f"/api/library/volumes/{volume_id}/pages/{idx}",
            }
            for idx, name in enumerate(pages)
        ]

    def read_page(self, volume_id: str, page_index: int) -> tuple[bytes, str]:
        if page_index < 0:
            raise MangaBadRequestError("Page index must be >= 0")

        volume_path = self._resolve_id_to_path(volume_id)
        kind = self._volume_kind(volume_path)

        if kind == "archive":
            return self._read_archive_page(volume_path, page_index)
        if kind == "directory":
            return self._read_directory_page(volume_path, page_index)

        raise MangaNotFoundError("Volume not found")

    def read_series_cover(self, series_id: str) -> tuple[bytes, str]:
        series_path = self._resolve_id_to_path(series_id)

        if series_path == self.root:
            raise MangaNotFoundError("Cover not found")
        if not series_path.exists() or not series_path.is_dir():
            raise MangaNotFoundError("Series not found")

        cover_path = self._find_cover_file(series_path)
        if not cover_path:
            raise MangaNotFoundError("Cover not found")

        data = cover_path.read_bytes()
        media_type = mimetypes.guess_type(cover_path.name)[0] or "application/octet-stream"
        return data, media_type

    def _read_archive_page(self, archive_path: Path, page_index: int) -> tuple[bytes, str]:
        pages = self._archive_pages(archive_path)
        if page_index >= len(pages):
            raise MangaNotFoundError("Page not found")

        page_name = pages[page_index]
        with zipfile.ZipFile(archive_path, "r") as archive:
            with archive.open(page_name, "r") as page:
                data = page.read()

        media_type = mimetypes.guess_type(page_name)[0] or "application/octet-stream"
        return data, media_type

    def _read_directory_page(self, directory_path: Path, page_index: int) -> tuple[bytes, str]:
        pages = self._directory_pages(directory_path)
        if page_index >= len(pages):
            raise MangaNotFoundError("Page not found")

        page_path = pages[page_index]
        data = page_path.read_bytes()
        media_type = mimetypes.guess_type(page_path.name)[0] or "application/octet-stream"
        return data, media_type

    def _archive_pages(self, archive_path: Path) -> list[str]:
        rel = archive_path.relative_to(self.root).as_posix()
        cached = self._archive_page_cache.get(rel)
        if cached is not None:
            return cached

        try:
            with zipfile.ZipFile(archive_path, "r") as archive:
                pages = [
                    name
                    for name in archive.namelist()
                    if not name.endswith("/") and Path(name).suffix.lower() in IMAGE_EXTENSIONS
                ]
        except zipfile.BadZipFile as exc:
            raise MangaBadRequestError(f"Corrupt archive: {archive_path.name}") from exc

        pages.sort(key=natural_sort_key)
        self._archive_page_cache[rel] = pages
        return pages

    def _directory_pages(self, directory_path: Path) -> list[Path]:
        rel = directory_path.relative_to(self.root).as_posix()
        cached = self._directory_page_cache.get(rel)
        if cached is not None:
            return cached

        pages = [
            p
            for p in directory_path.rglob("*")
            if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS
        ]
        pages.sort(key=lambda p: natural_sort_key(p.relative_to(directory_path).as_posix()))
        self._directory_page_cache[rel] = pages
        return pages

    def _find_volumes_in_directory(self, directory: Path) -> list[Path]:
        volumes: list[Path] = []
        for entry in self._sorted_entries(directory):
            kind = self._volume_kind(entry)
            if kind:
                volumes.append(entry)
        return volumes

    def _list_root_level_volumes(self) -> list[Path]:
        root_volumes: list[Path] = []
        for entry in self._sorted_entries(self.root):
            if entry.is_file() and self._is_archive(entry):
                root_volumes.append(entry)
                continue

            if not entry.is_dir():
                continue

            # If child entries already look like distinct volumes, this is
            # likely a series directory and should not be treated as a single.
            if self._find_volumes_in_directory(entry):
                continue

            if self._has_direct_image_files(entry):
                root_volumes.append(entry)

        return root_volumes

    @staticmethod
    def _sorted_entries(path: Path) -> list[Path]:
        return sorted(path.iterdir(), key=lambda p: natural_sort_key(p.name))

    @staticmethod
    def _is_archive(path: Path) -> bool:
        return path.is_file() and path.suffix.lower() in ARCHIVE_EXTENSIONS

    @staticmethod
    def _has_direct_image_files(path: Path) -> bool:
        image_count = 0
        for child in path.iterdir():
            if child.is_file() and child.suffix.lower() in IMAGE_EXTENSIONS:
                image_count += 1
                if image_count >= MIN_IMAGE_FILES_PER_VOLUME:
                    return True
        return False

    def _volume_kind(self, path: Path) -> str | None:
        rel_key = path.relative_to(self.root).as_posix() if self.root in path.parents else path.as_posix()
        if rel_key in self._volume_kind_cache:
            return self._volume_kind_cache[rel_key]

        kind: str | None = None
        if self._is_archive(path):
            kind = "archive"
        elif path.is_dir() and self._looks_like_manga_volume(path):
            kind = "directory"

        self._volume_kind_cache[rel_key] = kind
        return kind

    @staticmethod
    def _looks_like_manga_volume(path: Path) -> bool:
        image_count = 0
        for child in path.rglob("*"):
            if not child.is_file():
                continue

            ext = child.suffix.lower()
            if ext in VIDEO_EXTENSIONS:
                return False
            if ext in IMAGE_EXTENSIONS:
                image_count += 1

        return image_count >= MIN_IMAGE_FILES_PER_VOLUME

    def _volume_payload(self, path: Path, series_id: str) -> dict:
        relative_path = path.relative_to(self.root).as_posix()
        kind = self._volume_kind(path)
        if not kind:
            raise MangaNotFoundError(f"Unsupported volume type: {path}")

        return {
            "id": self._encode_relative_path(relative_path),
            "title": path.stem if path.is_file() else path.name,
            "relative_path": relative_path,
            "kind": kind,
            "series_id": series_id,
        }

    def _series_cover_url(self, relative_path: str) -> str | None:
        series_path = (self.root / relative_path).resolve()
        cover_path = self._find_cover_file(series_path)
        if not cover_path:
            return None
        series_id = self._encode_relative_path(relative_path)
        return f"/api/library/series/{series_id}/cover"

    @staticmethod
    def _find_cover_file(series_path: Path) -> Path | None:
        if not series_path.exists() or not series_path.is_dir():
            return None

        for base in COVER_BASENAMES:
            for ext in (".jpg", ".jpeg", ".png", ".webp"):
                candidate = series_path / f"{base}{ext}"
                if candidate.is_file():
                    return candidate

        # Fallback: choose the first image directly in series folder (not recursive)
        for entry in sorted(series_path.iterdir(), key=lambda p: natural_sort_key(p.name)):
            if entry.is_file() and entry.suffix.lower() in IMAGE_EXTENSIONS:
                return entry

        return None

    @staticmethod
    def _encode_relative_path(relative_path: str) -> str:
        encoded = base64.urlsafe_b64encode(relative_path.encode("utf-8")).decode("ascii")
        return encoded.rstrip("=")

    @staticmethod
    def _decode_relative_path(encoded_path: str) -> str:
        padding = "=" * (-len(encoded_path) % 4)
        try:
            decoded = base64.urlsafe_b64decode(encoded_path + padding).decode("utf-8")
        except Exception as exc:  # noqa: BLE001
            raise MangaBadRequestError("Invalid id format") from exc

        if not decoded:
            raise MangaBadRequestError("Invalid id format")

        return decoded

    def _resolve_id_to_path(self, encoded_path: str) -> Path:
        decoded = self._decode_relative_path(encoded_path)
        candidate = (self.root / decoded).resolve()

        if candidate != self.root and self.root not in candidate.parents:
            raise MangaBadRequestError("Invalid path")

        return candidate
