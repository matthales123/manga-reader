# Mac Handoff Checklist

Use this when you switch from Linux backend work to your Mac for Xcode work.

## Before You Move to Mac
- Backend tests pass on Linux: `make backend-test`
- Backend runs and is reachable from LAN: `http://<server-ip>:8080/health`
- `MANGA_ROOT` points to your actual NAS manga folder

## On Mac
1. Pull repo:
   - `git clone <your-repo-url>`
   - or if already cloned: `git pull origin main`
2. Create an iOS app in Xcode (SwiftUI lifecycle)
3. Copy files from `ios/Starter/` into your app target
4. Set base URL in `MangaReaderStarterApp.swift`:
   - `http://<linux-server-ip>:8080`
5. Ensure Mac/iPhone are on the same LAN as the Linux server
6. Run on iPhone (not simulator first if you want real network behavior)

## First Manual Validation Flow
1. Open app, verify series list loads
2. Open a series and verify volume list
3. Open a volume and verify page images render
4. Swipe through pages and confirm ordering

## If App Cannot Reach Backend
- Verify backend is running on Linux
- Verify Linux firewall/router allows port `8080`
- Verify iPhone and server are on same subnet
- Verify IP/port in app matches backend

## Codex Resume
- Open `docs/codex-session-handoff.md` and use the Resume Prompt section to continue quickly in a new Codex session.
