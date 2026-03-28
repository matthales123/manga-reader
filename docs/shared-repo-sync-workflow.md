# Shared Repo Sync Workflow (Linux + Mac/Xcode)

Use this workflow to keep one repo in sync while developing backend/simulator on Linux and iOS on your Mac.

## Recommended Structure
- Linux server: source of truth for backend + NAS access + preview testing
- Mac: source of truth for Xcode build/run and iPhone deployment
- Git remote (`origin`): sync point between both machines

## Linux -> Mac Flow
1. On Linux, complete your changes and validate:
   - `make backend-test`
   - `node --check preview/app.js`
2. Commit and push:
   - `git add .`
   - `git commit -m "Describe Linux changes"`
   - `git push origin main`
3. On Mac, pull latest:
   - `git pull origin main`
4. Open Xcode project/workspace from this repo and run.

## Mac -> Linux Flow
1. On Mac, make SwiftUI/Xcode updates.
2. Commit and push from Mac:
   - `git add .`
   - `git commit -m "Describe iOS changes"`
   - `git push origin main`
3. On Linux, pull latest:
   - `git pull origin main`
4. Re-run Linux validations if backend/shared files changed.

## Branch Strategy (Simple and Safe)
- Use `main` for stable work.
- For larger work, create short-lived branches:
  - `feature/offline-ui`
  - `feature/backend-cache`
- Merge quickly to avoid conflicts.

## Conflict Avoidance
- Avoid editing the same file on both machines before pulling.
- Pull before starting each session.
- Keep commit messages specific so rollbacks are easy.

## Xcode Notes
- Keep iOS starter/reference code in `ios/Starter/`.
- When you create the full Xcode app, keep it in-repo (example: `ios/App/`) so Linux + Mac share the same source tree.
- Xcode build artifacts (`DerivedData`) should stay out of git.

## Fast Session Start
On any machine:
1. `git pull origin main`
2. Read `docs/codex-session-handoff.md`
3. Continue from the "Next Priority Tasks" list.
