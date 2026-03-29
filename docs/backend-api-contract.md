# Backend API Contract (v0.1)

Base URL example: `http://192.168.1.50:8080`

## Health
`GET /health`

Response:
```json
{
  "status": "ok",
  "manga_root": "/mnt/jellyfin/Manga",
  "manga_root_exists": true
}
```

## List Series
`GET /api/library/series`

Response:
```json
{
  "items": [
    {
      "id": "T25lIFBpZWNl",
      "title": "One Piece",
      "relative_path": "One Piece",
      "volume_count": 109,
      "cover_url": "/api/library/series/T25lIFBpZWNl/cover"
    }
  ]
}
```

`cover_url` may be `null` when no cover image exists.

## List Volumes
`GET /api/library/series/{series_id}/volumes`

Response:
```json
{
  "items": [
    {
      "id": "T25lIFBpZWNlL1ZvbCAwMDE",
      "title": "Vol 001",
      "relative_path": "One Piece/Vol 001",
      "kind": "directory",
      "series_id": "T25lIFBpZWNl"
    }
  ]
}
```

## Get Series Cover
`GET /api/library/series/{series_id}/cover`

Response:
- raw image bytes (`image/jpeg`, `image/png`, etc.)
- `404` when no cover exists

Cover file lookup inside each series folder:
- `cover.jpg` / `cover.jpeg` / `cover.png` / `cover.webp`
- `folder.jpg` / `folder.jpeg` / `folder.png` / `folder.webp`
- `poster.jpg` / `poster.jpeg` / `poster.png` / `poster.webp`
- fallback: first image file directly in the series folder

## Get Series Arcs
`GET /api/library/series/{series_id}/arcs`

Response:

```json
{
  "items": [
    {
      "id": "aot-trost",
      "name": "Trost Arc",
      "start_chapter": 3,
      "end_chapter": 14,
      "order": 2
    }
  ]
}
```

Notes:
- `start_chapter` and `end_chapter` are nullable numeric values.
- Returns `items: []` when no arc data is available for the series.
- Server caches normalized arc responses under `ARC_INDEX_ROOT` (default: `backend/arc_index`).
- For unknown series, server auto-inferrs chapter bucket arcs from chapter-style names (`Chapter 1`, `Episode 1`, etc.).

## Sync Arc Cache
`POST /api/library/arcs/sync`

Query params:
- `force_refresh` (optional, default `false`)

Response:

```json
{
  "series_total": 24,
  "created": 24,
  "refreshed": 0,
  "unchanged": 0,
  "errors": []
}
```

Background behavior:
- On backend startup, arc cache sync runs once when `ARC_SYNC_ON_STARTUP=true`.
- Then runs periodically every `ARC_SYNC_INTERVAL_SECONDS` (minimum loop interval is 30 seconds).

## List Pages
`GET /api/library/volumes/{volume_id}/pages`

Response:
```json
{
  "items": [
    {
      "index": 0,
      "name": "001.jpg",
      "url": "/api/library/volumes/T25lIFBpZWNlL1ZvbCAwMDE/pages/0"
    }
  ]
}
```

## Get Page Image
`GET /api/library/volumes/{volume_id}/pages/{page_index}`

Response:
- raw image bytes (`image/jpeg`, `image/png`, etc.)

## Error Codes
- `400`: Invalid ID/path or bad request
- `404`: Series/volume/page not found
