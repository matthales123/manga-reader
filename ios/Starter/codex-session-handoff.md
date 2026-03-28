# Codex Session Handoff

Use this file to resume work quickly from Linux or Mac.

## Current Project State
- Monorepo root: `/home/mhales/manga-reader`
- Backend: FastAPI (`backend/`)
- Browser simulator: `preview/`
- SwiftUI starter files: `ios/Starter/`
- NAS-backed manga library via `MANGA_ROOT`

## Implemented So Far
1. Backend browsing/reader endpoints for series, volumes, pages.
2. Series cover support:
   - `cover.jpg`, `folder.jpg`, `poster.jpg` detection.
   - API route: `GET /api/library/series/{series_id}/cover`
3. Simulator improvements:
   - Reader refresh keeps current page.
   - Theme modes (system/light/dark).
   - Header refresh on top-right.
   - Back behavior and progress persistence.
4. SwiftUI starter improvements:
   - Theme switcher with persisted preference.
   - Reader back button persists position.
   - Volume progress UI.
   - Cover thumbnails from backend.
5. Offline iPhone reading support:
   - Per-volume download to app storage.
   - Offline fallback in library and volume lists.
   - Reader prefers local pages when available.
   - Swipe actions to download/remove offline volumes.

## Important File Map
- Backend core: `backend/app/library.py`, `backend/app/main.py`
- Backend tests: `backend/tests/test_api.py`
- Simulator: `preview/index.html`, `preview/styles.css`, `preview/app.js`
- SwiftUI app entry: `ios/Starter/MangaReaderStarterApp.swift`
- SwiftUI library/volumes/reader:
  - `ios/Starter/LibraryView.swift`
  - `ios/Starter/VolumeListView.swift`
  - `ios/Starter/ReaderView.swift`
- SwiftUI shared models/services:
  - `ios/Starter/AppTheme.swift`
  - `ios/Starter/ReadingProgressStore.swift`
  - `ios/Starter/OfflineLibraryStore.swift`
  - `ios/Starter/MangaAPI.swift`
  - `ios/Starter/Models.swift`

## Validation Commands
- Backend tests:
  - `make backend-test`
- Preview syntax check:
  - `node --check preview/app.js`

## Next Priority Tasks
1. Create/open full Xcode iOS app target on Mac and copy `ios/Starter/` files in.
2. Point `MangaReaderStarterApp.swift` base URL to Linux server LAN IP.
3. Run on iPhone and verify:
   - Online read flow
   - Offline download + airplane-mode read flow
4. Optional: Add cover image caching and prefetch queue for faster page turns.
5. Optional: Move progress/offline metadata from local-only to backend sync.

## Resume Prompt (Copy/Paste)
Continue the manga-reader project using `docs/codex-session-handoff.md` and the latest repo state. Prioritize iOS/Xcode integration and verify offline reading on iPhone while keeping Linux backend compatibility.
