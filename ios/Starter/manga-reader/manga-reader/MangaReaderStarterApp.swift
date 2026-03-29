import SwiftUI
import Combine
import UserNotifications

@MainActor
@main
struct MangaReaderStarterApp: App {
    private enum ServerConfiguration {
        static let defaultBaseURLString = "http://192.168.0.239:8080"
        static let enableUserDefaultsOverride = false
        static let userDefaultsKey = "manga_reader_api_base_url"

        static var baseURL: URL {
            if enableUserDefaultsOverride,
               let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
               let url = URL(string: raw)
            {
                return url
            }

            guard let url = URL(string: defaultBaseURLString) else {
                preconditionFailure("Invalid default API base URL: \(defaultBaseURLString)")
            }
            return url
        }
    }

    private let api = MangaAPI(baseURL: ServerConfiguration.baseURL)

    @StateObject private var settings = AppSettings()
    @StateObject private var readingProgress = ReadingProgressStore()
    @StateObject private var offlineLibrary = OfflineLibraryStore()
    @StateObject private var downloadQueue = DownloadQueueStore()
    @State private var didRequestNotificationPermission = false

    var body: some Scene {
        WindowGroup {
            LibraryView(api: api)
                .environmentObject(settings)
                .environmentObject(readingProgress)
                .environmentObject(offlineLibrary)
                .environmentObject(downloadQueue)
                .preferredColorScheme(settings.selectedTheme.colorScheme)
                .onAppear {
                    api.updateBaseURL(settings.serverURL)
                }
                .onChange(of: settings.serverURLString) { _, _ in
                    api.updateBaseURL(settings.serverURL)
                }
                .task {
                    guard !didRequestNotificationPermission else { return }
                    didRequestNotificationPermission = true
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound, .badge]
                    )
                }
        }
    }
}
