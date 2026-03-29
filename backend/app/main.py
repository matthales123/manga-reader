from __future__ import annotations

import asyncio
import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response

from .arcs import ArcCatalog
from .library import MangaBadRequestError, MangaLibrary, MangaNotFoundError


def parse_allowed_origins() -> list[str]:
    raw = os.getenv("CORS_ALLOW_ORIGINS", "*")
    origins = [item.strip() for item in raw.split(",") if item.strip()]
    return origins or ["*"]


MANGA_ROOT = Path(os.getenv("MANGA_ROOT", "/home/mhales/NAS/Manga"))
library = MangaLibrary(MANGA_ROOT)
ARC_INDEX_ROOT = Path(os.getenv("ARC_INDEX_ROOT", str((Path(__file__).resolve().parents[1] / "arc_index"))))
arc_catalog = ArcCatalog(library=library, cache_root=ARC_INDEX_ROOT)
ARC_SYNC_INTERVAL_SECONDS = int(os.getenv("ARC_SYNC_INTERVAL_SECONDS", "300"))
ARC_SYNC_ON_STARTUP = os.getenv("ARC_SYNC_ON_STARTUP", "true").lower() in {"1", "true", "yes", "on"}

logger = logging.getLogger(__name__)
arc_sync_task: asyncio.Task | None = None
arc_warmup_task: asyncio.Task | None = None

app = FastAPI(
    title="Manga Reader Backend",
    description="Local-first API for browsing manga stored on a NAS",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=parse_allowed_origins(),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def run_arc_sync_once(force_refresh: bool = False) -> dict:
    summary = await asyncio.to_thread(arc_catalog.sync_all_series, force_refresh=force_refresh)
    logger.info("Arc metadata sync summary: %s", summary)
    return summary


async def arc_sync_loop() -> None:
    interval = max(30, ARC_SYNC_INTERVAL_SECONDS)
    await asyncio.sleep(interval)
    while True:
        try:
            await run_arc_sync_once(force_refresh=False)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Arc sync loop iteration failed: %s", exc)
        await asyncio.sleep(interval)


@app.on_event("startup")
async def startup_tasks() -> None:
    global arc_sync_task, arc_warmup_task
    if ARC_SYNC_ON_STARTUP:
        arc_warmup_task = asyncio.create_task(run_arc_sync_once(force_refresh=False))
    if ARC_SYNC_INTERVAL_SECONDS > 0:
        arc_sync_task = asyncio.create_task(arc_sync_loop())


@app.on_event("shutdown")
async def shutdown_tasks() -> None:
    global arc_sync_task, arc_warmup_task
    if arc_sync_task is not None:
        arc_sync_task.cancel()
        arc_sync_task = None
    if arc_warmup_task is not None:
        arc_warmup_task.cancel()
        arc_warmup_task = None


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "manga_root": str(library.root),
        "manga_root_exists": library.root.exists(),
    }


@app.get("/api/library/series")
def list_series() -> dict:
    return {"items": library.list_series()}


@app.get("/api/library/series/{series_id}/volumes")
def list_volumes(series_id: str) -> dict:
    try:
        items = library.list_volumes(series_id)
    except MangaNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except MangaBadRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"items": items}


@app.get("/api/library/series/{series_id}/cover")
def read_series_cover(series_id: str) -> Response:
    try:
        data, media_type = library.read_series_cover(series_id)
    except MangaNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except MangaBadRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return Response(
        content=data,
        media_type=media_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )


@app.get("/api/library/series/{series_id}/arcs")
def list_series_arcs(series_id: str) -> dict:
    try:
        items = arc_catalog.list_arcs(series_id)
    except MangaNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except MangaBadRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"items": items}


@app.post("/api/library/arcs/sync")
async def sync_series_arcs(force_refresh: bool = False) -> dict:
    summary = await run_arc_sync_once(force_refresh=force_refresh)
    return summary


@app.get("/api/library/volumes/{volume_id}/pages")
def list_pages(volume_id: str) -> dict:
    try:
        items = library.list_pages(volume_id)
    except MangaNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except MangaBadRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"items": items}


@app.get("/api/library/volumes/{volume_id}/pages/{page_index}")
def read_page(volume_id: str, page_index: int) -> Response:
    try:
        data, media_type = library.read_page(volume_id, page_index)
    except MangaNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except MangaBadRequestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return Response(
        content=data,
        media_type=media_type,
        headers={"Cache-Control": "public, max-age=86400"},
    )
