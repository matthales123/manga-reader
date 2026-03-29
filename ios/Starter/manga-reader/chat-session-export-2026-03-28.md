# Chat Session Export - 2026-03-28

This file captures the work completed in this Linux Codex session so a new Mac/Xcode Codex session can continue without losing context.

## Session Scope
- User goal: Build an iPhone manga reader app backed by a Linux-hosted NAS library.
- Constraint clarified: Xcode cannot run on Linux, so Linux handles backend + simulator + repo setup, while Mac handles Xcode/iPhone build.
- Outcome: Backend, browser simulator, SwiftUI starter, offline-download support, and shared Git workflow are all prepared.

## Architecture Decisions
- Monorepo layout:
  - `backend/` FastAPI service for NAS manga browsing and page streaming
  - `preview/` browser-based iPhone-style simulator for UI/flow iteration
  - `ios/Starter/` SwiftUI starter files to import into Xcode app target
  - `docs/` handoff + contracts + workflow
- Data source: NAS path via `MANGA_ROOT`
- iOS network model: app reads backend via `http://<linux-server-ip>:8080`

## Implemented Features
1. Backend API for library browsing and reading:
   - `GET /api/library/series`
   - `GET /api/library/series/{series_id}/volumes`
   - `GET /api/library/volumes/{volume_id}/pages`
   - `GET /api/library/volumes/{volume_id}/pages/{page_index}`
2. Series cover support:
   - Added `cover_url` in series payload
   - Added `GET /api/library/series/{series_id}/cover`
   - Cover detection order: `cover.*`, `folder.*`, `poster.*`, then first direct image in series folder
3. Simulator UX updates:
   - Reader refresh keeps current page
   - Theme toggle: `system`, `light`, `dark`
   - Header refresh button placed top-right
   - Reader back behavior saves progress
   - Volume progress labels and per-volume progress persistence
4. SwiftUI starter updates:
   - Theme toggle support with persisted app preference
   - Cover thumbnails on series/volume rows
   - Reader refresh cache-bust and back button save
   - Volume progress indicators
5. Offline reading support on iPhone:
   - Added `OfflineLibraryStore.swift`
   - Per-volume download to app storage
   - Swipe actions in volume list: `Download` / `Remove`
   - Reader prefers local pages when downloaded
   - Offline fallback in library and volume list when backend is unreachable
6. Git workflow setup:
   - Repo initialized with initial commit on `main`
   - Remote configured as `git@github.com:matthales123/manga-reader.git`

## Key Files
- Backend:
  - `backend/app/main.py`
  - `backend/app/library.py`
  - `backend/tests/test_api.py`
- Simulator:
  - `preview/index.html`
  - `preview/styles.css`
  - `preview/app.js`
- SwiftUI starter:
  - `ios/Starter/MangaReaderStarterApp.swift`
  - `ios/Starter/LibraryView.swift`
  - `ios/Starter/VolumeListView.swift`
  - `ios/Starter/ReaderView.swift`
  - `ios/Starter/OfflineLibraryStore.swift`
  - `ios/Starter/AppTheme.swift`
  - `ios/Starter/ReadingProgressStore.swift`
  - `ios/Starter/MangaAPI.swift`
  - `ios/Starter/Models.swift`
  - `ios/Starter/CoverThumbnailView.swift`

## Validation Completed
- Linux backend tests: `make backend-test` passed (`4 passed`)
- Preview JS syntax check: `node --check preview/app.js` passed

## Current State For Mac/Xcode
- User has cloned repo on Mac and updated server IP in SwiftUI app entry.
- Next work is Xcode-side integration and running on physical iPhone.
- If app cannot connect, likely causes are:
  - App Transport Security blocking HTTP
  - Signing/team/developer mode setup
  - Phone not reaching Linux backend on LAN

## Mac Run Checklist
1. Ensure only iOS app files are in target membership.
2. Ensure only one `@main` app entry file in target.
3. Confirm base URL points to Linux server IP and backend is running.
4. In iPhone Safari, verify `http://<linux-ip>:8080/health` loads.
5. Add ATS dev exception if HTTP is blocked.
6. Verify Apple signing team, unique bundle ID, iPhone developer mode.
7. Run app on iPhone and validate:
   - Library/volumes/pages load online
   - Download a volume with swipe action
   - Enable airplane mode and verify offline read

## Related Docs
- `docs/codex-session-handoff.md`
- `docs/shared-repo-sync-workflow.md`
- `docs/mac-handoff-checklist.md`
- `docs/backend-api-contract.md`
- `docs/swiftui-client-starter.md`

## Resume Prompt For New Mac Codex Session
Continue the manga-reader project using `docs/chat-session-export-2026-03-28.md` and `docs/codex-session-handoff.md`. Focus on Xcode integration, iPhone deployment, ATS/signing/network troubleshooting, and final validation of offline volume downloads and airplane-mode reading.
