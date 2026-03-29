# Manga Reader - Full Session Handoff

This document captures the full implementation state from this chat so another Codex session can continue without re-discovery.

## Current App Status

The iOS app is currently building and running with:

- Redesigned light/dark UI theme system (`AppChrome` + theme toggle).
- Header/title alignment fixes and long-title wrapping.
- Continue Reading flow improved to reopen exact chapter/page.
- Reader chapter navigation (prev/next chapter and chapter picker).
- Download queue, retry failed, and local notification support.
- Settings page extended (downloads, queue, collections, network, reader controls, debug toggle, etc.).
- Library/volume caching to avoid empty loading states on return.
- Offline download storage and queue integration.
- Reader zoom/pan behavior stabilized after multiple iterations.
- Arc section grouping support (now prepared to use server-provided arc metadata with local cache fallback).

## Key Files Added/Extended

- `manga-reader/AppTheme.swift`  
  - App settings persistence (theme, server URL, reader settings, collections, debug toggle, etc.).
- `manga-reader/LibraryView.swift`  
  - Continue reading card improvements, collection assignment, settings integration.
- `manga-reader/VolumeListView.swift`  
  - Filtering/sorting/download actions, scroll restore, chapter list grouping by arc sections.
- `manga-reader/ReaderView.swift`  
  - In-place chapter switching, zoom container use, page progress persistence.
- `manga-reader/MangaAPI.swift`  
  - Existing series/volume/pages API calls + new `fetchStoryArcs(seriesID:)`.
- `manga-reader/MangaReaderStarterApp.swift`  
  - App-level environment object wiring + notification permission request.
- `manga-reader/Models.swift`  
  - Added `StoryArc` and `ArcListResponse`.
- `LibraryCacheStore.swift` (repo root)  
  - Added cached arc load/save helpers.
- `SettingsView.swift` (repo root)  
  - Added reader debug overlay toggle in settings.
- `DownloadQueueStore.swift` (repo root)  
  - Retry-failed flow + status behavior.
- `ZoomableImageView.swift` (repo root)  
  - Current zoom/pan container + optional debug overlay.

## Important Path Note

Project uses a mixed path layout:

- Main app source files are in `manga-reader/`
- Some newer files are at repo root (`SettingsView.swift`, `LibraryCacheStore.swift`, `DownloadQueueStore.swift`, `ZoomableImageView.swift`)

This is intentional in the current workspace and builds successfully.

## Reader / Zoom Debug Outcome

We validated via on-screen debug overlay:

- Remote loading works (`HTTP 200`, image decoded).
- Offline loading works (`local.exists=true`, decoded).
- Prior blank-page behavior was layout/zoom-related (not NAS/network/decode).

Current behavior:

- Pages load.
- Fit behavior is controlled in `ZoomableImageView`.
- Debug overlay is now toggleable in Settings and defaults OFF.

## Arc Grouping Feature (App Side)

Implemented app-side arc pipeline:

1. Try resolved arcs from cache/API (`StoryArc`).
2. If no resolved arcs, fallback to inferred grouping from `relativePath`.
3. Group chapters into visible sections in `VolumeListView`.

### New API expected by app

`GET /api/library/series/{seriesID}/arcs`

Response:

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

`start_chapter` / `end_chapter` may be numeric chapter values (supports decimals).

## Server-Side Work Needed Next

To complete automatic arc grouping without user setup:

1. Implement `GET /api/library/series/{seriesID}/arcs`.
2. Resolve series title -> external metadata source for arc ranges.
3. Normalize arcs to app schema (`id`, `name`, `start_chapter`, `end_chapter`, `order`).
4. Cache on server side to avoid repeated upstream lookups.
5. Return deterministic ordering and stable IDs.

Optional hardening:

- Add `last_updated` metadata in response.
- Add server-side override file for manual arc corrections.
- Add title alias mapping for difficult series matches.

## Suggested Server JSON Cache Layout

Per-series JSON cache file:

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

## Other Major Features Implemented During This Session

- Continue reading now intended to resume exact chapter/page.
- Return-to-list scroll restoration near last opened volume.
- Collections support:
  - create/delete collections in settings
  - assign series to collections
  - filter library by collection
- Download queue improvements:
  - queue status display
  - retry failed
  - clear completed
- Storage visibility in settings:
  - total offline size
  - per-series downloaded chapter count and size
- Reader controls:
  - reading direction
  - zoom mode
  - keep screen awake

## Known Follow-Up Tasks

1. Remove temporary debug instrumentation completely once stable (if desired).
2. Validate arc endpoint integration with real backend data.
3. Improve chapter-number parser if your chapter naming is non-standard.
4. Add tests for:
   - arc section assignment by chapter ranges
   - fallback grouping when arc API unavailable

## Build Verification

Latest project builds were successful via Xcode build tool after each major patch.

