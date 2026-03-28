import SwiftUI

@main
struct MangaReaderStarterApp: App {
    private let api = MangaAPI(baseURL: URL(string: "http://YOUR_SERVER_IP:8080")!)

    @StateObject private var settings = AppSettings()
    @StateObject private var readingProgress = ReadingProgressStore()
    @StateObject private var offlineLibrary = OfflineLibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView(api: api)
                .environmentObject(settings)
                .environmentObject(readingProgress)
                .environmentObject(offlineLibrary)
                .preferredColorScheme(settings.selectedTheme.colorScheme)
        }
    }
}
