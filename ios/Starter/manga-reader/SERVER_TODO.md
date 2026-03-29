# Server TODO For Manga Reader

## Goal

Enable automatic story-arc grouping in the iOS app without user manual setup.

## Required Endpoint

Implement:

- `GET /api/library/series/{seriesID}/arcs`

Response shape:

```json
{
  "items": [
    {
      "id": "aot-trost",
      "name": "Trost Arc",
      "start_chapter": 1,
      "end_chapter": 50,
      "order": 1
    }
  ]
}
```

## Field Notes

- `id`: stable unique string for arc.
- `name`: user-facing arc title.
- `start_chapter`: nullable numeric (supports decimal chapters).
- `end_chapter`: nullable numeric.
- `order`: nullable integer for display ordering.

## Behavior Expected By App

1. App loads cached arcs first.
2. App requests endpoint above.
3. If non-empty response, app replaces cached arcs and groups chapters by chapter-number range.
4. If endpoint unavailable/empty, app falls back to inferred grouping from file path.

## Suggested Server Architecture

1. Resolve series title/aliases to external metadata source.
2. Normalize external arc data into app schema.
3. Persist per-series cache JSON.
4. Serve cached/normalized result quickly from API.

## Suggested Server Cache File

Path:

- `arc_index/<series_id>.json`

Example:

```json
{
  "series_id": "aot",
  "series_title": "Attack on Titan",
  "source": "resolver-name",
  "updated_at": "2026-03-29T00:00:00Z",
  "items": [
    { "id": "aot-arc-1", "name": "Arc 1", "start_chapter": 1, "end_chapter": 34, "order": 1 },
    { "id": "aot-arc-2", "name": "Arc 2", "start_chapter": 35, "end_chapter": 50, "order": 2 }
  ]
}
```

## Validation Checklist

- [ ] Returns 200 with `items` array.
- [ ] Handles series with no arc data (`items: []`).
- [ ] Stable IDs/order across calls.
- [ ] Numeric chapter ranges parse cleanly.
- [ ] CORS/firewall/network path still compatible with iOS app LAN access.

## Current App Integration Points

- `manga-reader/MangaAPI.swift`: `fetchStoryArcs(seriesID:)`
- `manga-reader/Models.swift`: `StoryArc`, `ArcListResponse`
- `LibraryCacheStore.swift`: `loadArcs`, `saveArcs`
- `manga-reader/VolumeListView.swift`: arc grouping pipeline + fallback

