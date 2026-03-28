# UI Simulator Guide

Use this browser simulator to preview the app UX before starting Xcode.

## Start Simulator

```bash
cd /home/mhales/manga-reader
make preview-run
```

Open in browser:
- `http://127.0.0.1:4173` (from server GUI session)
- `http://<server-lan-ip>:4173` (from another device on LAN)

## Connect to Real Backend
1. Start backend API (`make backend-run`)
2. In simulator, set API base URL to your backend (example: `http://192.168.1.50:8080`)
3. Click `Connect`

## Demo Mode
If backend is offline, enable `Use demo data` in the simulator panel to test UI behavior.

## What It Simulates
- Library list screen
- Volume list screen
- Reader screen with page navigation
- Back navigation that preserves reading location
- Top-right refresh action on each screen
- Loading, empty, and error states
- Theme modes: system, light, dark
- Volume progress labels (`Read X/Y` and `Complete`)

## Reader Controls
- Buttons: `Previous` / `Next`
- Keyboard: `Left` / `Right` arrow keys
- Touch: swipe left/right on the page area
- Refresh button in reader reloads the current page image and keeps your position
