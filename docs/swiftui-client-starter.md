# SwiftUI Client Starter

The ready-to-use starter files live in `ios/Starter/`:
- `MangaReaderStarterApp.swift`
- `MangaAPI.swift`
- `Models.swift`
- `LibraryView.swift`
- `VolumeListView.swift`
- `ReaderView.swift`
- `AppTheme.swift`
- `ReadingProgressStore.swift`
- `CoverThumbnailView.swift`
- `OfflineLibraryStore.swift`

## Use on Mac (Xcode)
1. Create a new iOS App project (SwiftUI)
2. Copy files from `ios/Starter/` into your app target
3. Set backend URL in `MangaReaderStarterApp.swift` to your Linux server IP:
   - `http://<server-ip>:8080`
4. Run on iPhone and confirm series/volume/page loading

## Notes
- These starter files intentionally use `AsyncImage` first for simplicity.
- After baseline validation, replace with a custom image cache for smoother paging.
- Theme mode can be changed in-app: `System`, `Light`, `Dark`.
- Reader progress is saved locally in `UserDefaults` per volume.
- Volumes can be downloaded into app storage for offline reading and removed later.
- In `VolumeListView`, swipe a volume row left to `Download` or `Remove` offline content.
