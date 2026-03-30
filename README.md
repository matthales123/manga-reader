# Manga Reader Monorepo

Local-first manga reader project with:
- Linux-hosted backend API (FastAPI)
- iOS app code (SwiftUI) to be built on macOS/Xcode
- NAS storage as the source of manga volumes

## Repository Layout

```text
manga-reader/
  backend/                # FastAPI service
  ios/                    # SwiftUI app files (to be opened in Xcode on Mac)
  preview/                # Browser-based iPhone UI simulator
  docs/                   # API notes and setup handoff docs
  docker-compose.yml      # Optional containerized backend run
  Makefile                # Common dev commands
```

## Backend Features
- Supports manga volumes as `.cbz`/`.zip` or image folders
- Lists series, volumes, pages
- Serves optional series cover images (`cover.jpg`, `folder.jpg`, `poster.jpg`)
- Serves story-arc metadata for supported series via `/api/library/series/{series_id}/arcs`
- Auto-generates named arc templates for new unknown series (`backend/arc_templates/*.json`) so new additions get arc sections immediately
- Streams page image bytes for reader display
- Rejects invalid/traversal-style path access

## Linux Setup (Server)

1. Configure environment:

```bash
cd /home/mhales/manga-reader/backend
cp .env.example .env
```

2. Edit `.env` and set your NAS manga path:

```env
MANGA_ROOT=/mnt/jellyfin/Manga
CORS_ALLOW_ORIGINS=*
HOST=0.0.0.0
PORT=8080
ARC_SYNC_ON_STARTUP=true
ARC_SYNC_INTERVAL_SECONDS=60
ARC_INDEX_ROOT=/home/mhales/manga-reader/backend/arc_index
ARC_TEMPLATE_ROOT=/home/mhales/manga-reader/backend/arc_templates
```

3. Install dependencies:

```bash
cd /home/mhales/manga-reader
make backend-install
```

4. Run tests:

```bash
cd /home/mhales/manga-reader
make backend-test
```

5. Start API:

```bash
cd /home/mhales/manga-reader
make backend-run
```

Or install persistent user service:

```bash
cd /home/mhales/manga-reader
make backend-service-install
```

6. Open docs:

- `http://<server-lan-ip>:8080/docs`
- Systemd service guide: `docs/backend-systemd-service.md`

## Optional Docker Run

```bash
cd /home/mhales/manga-reader
HOST_MANGA_ROOT=/mnt/jellyfin/Manga docker compose up --build
```

## API Endpoints
- `GET /health`
- `GET /api/library/series`
- `GET /api/library/series/{series_id}/volumes`
- `GET /api/library/series/{series_id}/cover`
- `GET /api/library/series/{series_id}/arcs`
- `GET /api/library/volumes/{volume_id}/pages`
- `GET /api/library/volumes/{volume_id}/pages/{page_index}`

## iOS Handoff
- Starter SwiftUI files are in `ios/Starter/`
- On your Mac, create a new iOS App in Xcode and copy those files in.
- Replace `YOUR_SERVER_IP` in the app bootstrap with your Linux server LAN IP.
- The starter includes per-volume offline download support for airplane-mode reading.

Additional handoff doc: `docs/mac-handoff-checklist.md`
Shared sync workflow: `docs/shared-repo-sync-workflow.md`
Codex resume context: `docs/codex-session-handoff.md`
Full session export: `docs/chat-session-export-2026-03-28.md`

## UI Simulator (No Xcode Needed)
- Browser-based iPhone UI preview lives in `preview/`
- Run it with:

```bash
cd /home/mhales/manga-reader
make preview-run
```

- Open: `http://<server-lan-ip>:4173`
- You can connect it to your backend API or toggle demo mode for mock data.
- Includes library/volume/reader flow, top-right refresh, theme toggle (system/light/dark), and per-volume progress indicators.

Simulator guide: `docs/ui-simulator.md`

## Git Workflow

```bash
cd /home/mhales/manga-reader
git status
git add .
git commit -m "Describe change"
```

## Notes
- Xcode/iOS builds require macOS.
- Keep content legal and licensed for personal use.
- For series artwork, place a local cover image in each series folder (for example `cover.jpg`).
