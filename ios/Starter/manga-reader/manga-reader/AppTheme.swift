import SwiftUI
import Combine
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum ReaderDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        }
    }
}

enum ReaderZoomMode: String, CaseIterable, Identifiable {
    case fitWidth
    case fitPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitWidth: return "Fit Width"
        case .fitPage: return "Fit Page"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let storageThemeKey = "manga_reader_theme"
    private let storageServerURLKey = "manga_reader_server_url"
    private let storageWiFiOnlyDownloadsKey = "manga_reader_wifi_only_downloads"
    private let storageAutoDeleteReadDaysKey = "manga_reader_auto_delete_read_days"
    private let storageKeepScreenAwakeKey = "manga_reader_keep_screen_awake"
    private let storageReaderDirectionKey = "manga_reader_reader_direction"
    private let storageReaderZoomModeKey = "manga_reader_reader_zoom_mode"
    private let storageMetadataScaleKey = "manga_reader_metadata_scale"
    private let storageLocalNetworkOnlyKey = "manga_reader_local_network_only"
    private let storageShowReaderDebugOverlayKey = "manga_reader_show_reader_debug_overlay"
    private let storageFavoriteSeriesIDsKey = "manga_reader_favorite_series_ids"
    private let storageCollectionsKey = "manga_reader_collections"

    static let defaultServerURL = "http://192.168.0.239:8080"

    @Published var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: storageThemeKey)
        }
    }

    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: storageServerURLKey)
        }
    }

    @Published var wifiOnlyDownloads: Bool {
        didSet {
            UserDefaults.standard.set(wifiOnlyDownloads, forKey: storageWiFiOnlyDownloadsKey)
        }
    }

    @Published var autoDeleteReadAfterDays: Int {
        didSet {
            UserDefaults.standard.set(autoDeleteReadAfterDays, forKey: storageAutoDeleteReadDaysKey)
        }
    }

    @Published var keepScreenAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: storageKeepScreenAwakeKey)
        }
    }

    @Published var readerDirection: ReaderDirection {
        didSet {
            UserDefaults.standard.set(readerDirection.rawValue, forKey: storageReaderDirectionKey)
        }
    }

    @Published var readerZoomMode: ReaderZoomMode {
        didSet {
            UserDefaults.standard.set(readerZoomMode.rawValue, forKey: storageReaderZoomModeKey)
        }
    }

    @Published var metadataTextScale: Double {
        didSet {
            UserDefaults.standard.set(metadataTextScale, forKey: storageMetadataScaleKey)
        }
    }

    @Published var localNetworkOnly: Bool {
        didSet {
            UserDefaults.standard.set(localNetworkOnly, forKey: storageLocalNetworkOnlyKey)
        }
    }

    @Published var showReaderDebugOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showReaderDebugOverlay, forKey: storageShowReaderDebugOverlayKey)
        }
    }

    @Published private(set) var favoriteSeriesIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(favoriteSeriesIDs), forKey: storageFavoriteSeriesIDsKey)
        }
    }

    @Published private(set) var collections: [String: Set<String>] {
        didSet {
            let encoded = collections.mapValues { Array($0) }
            UserDefaults.standard.set(encoded, forKey: storageCollectionsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: storageThemeKey)
        selectedTheme = AppTheme(rawValue: raw ?? "") ?? .system

        let rawServerURL = UserDefaults.standard.string(forKey: storageServerURLKey)
        serverURLString = rawServerURL ?? Self.defaultServerURL

        wifiOnlyDownloads = UserDefaults.standard.object(forKey: storageWiFiOnlyDownloadsKey) as? Bool ?? true
        autoDeleteReadAfterDays = UserDefaults.standard.object(forKey: storageAutoDeleteReadDaysKey) as? Int ?? 0
        keepScreenAwake = UserDefaults.standard.object(forKey: storageKeepScreenAwakeKey) as? Bool ?? true

        let rawDirection = UserDefaults.standard.string(forKey: storageReaderDirectionKey)
        readerDirection = ReaderDirection(rawValue: rawDirection ?? "") ?? .leftToRight

        let rawZoomMode = UserDefaults.standard.string(forKey: storageReaderZoomModeKey)
        readerZoomMode = ReaderZoomMode(rawValue: rawZoomMode ?? "") ?? .fitPage

        let rawScale = UserDefaults.standard.object(forKey: storageMetadataScaleKey) as? Double ?? 1.0
        metadataTextScale = min(max(rawScale, 0.8), 1.4)

        localNetworkOnly = UserDefaults.standard.object(forKey: storageLocalNetworkOnlyKey) as? Bool ?? true
        showReaderDebugOverlay = UserDefaults.standard.object(forKey: storageShowReaderDebugOverlayKey) as? Bool ?? false

        let rawFavoriteIDs = UserDefaults.standard.array(forKey: storageFavoriteSeriesIDsKey) as? [String] ?? []
        favoriteSeriesIDs = Set(rawFavoriteIDs)

        let rawCollections = UserDefaults.standard.dictionary(forKey: storageCollectionsKey) as? [String: [String]] ?? [:]
        collections = rawCollections.mapValues { Set($0) }
    }

    var serverURL: URL {
        if let url = URL(string: serverURLString), url.scheme != nil {
            return url
        }
        return URL(string: Self.defaultServerURL) ?? URL(fileURLWithPath: "/")
    }

    func isFavoriteSeries(_ seriesID: String) -> Bool {
        favoriteSeriesIDs.contains(seriesID)
    }

    func toggleFavoriteSeries(_ seriesID: String) {
        if favoriteSeriesIDs.contains(seriesID) {
            favoriteSeriesIDs.remove(seriesID)
        } else {
            favoriteSeriesIDs.insert(seriesID)
        }
    }

    var collectionNames: [String] {
        collections.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func addCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if collections[trimmed] == nil {
            collections[trimmed] = []
        }
    }

    func removeCollection(named name: String) {
        collections.removeValue(forKey: name)
    }

    func isSeries(_ seriesID: String, inCollection name: String) -> Bool {
        collections[name]?.contains(seriesID) ?? false
    }

    func toggleSeries(_ seriesID: String, inCollection name: String) {
        guard var set = collections[name] else { return }
        if set.contains(seriesID) {
            set.remove(seriesID)
        } else {
            set.insert(seriesID)
        }
        collections[name] = set
    }
}

enum AppChrome {
    static let background = dynamic(
        light: UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
    )
    static let surface = dynamic(
        light: UIColor(white: 1.0, alpha: 0.72),
        dark: UIColor(red: 0.16, green: 0.19, blue: 0.22, alpha: 0.85)
    )
    static let card = dynamic(
        light: UIColor(white: 1.0, alpha: 0.64),
        dark: UIColor(red: 0.13, green: 0.16, blue: 0.19, alpha: 0.9)
    )
    static let border = dynamic(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.14)
    )
    static let title = dynamic(
        light: UIColor(red: 0.16, green: 0.19, blue: 0.22, alpha: 1),
        dark: UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
    )
    static let subtitle = dynamic(
        light: UIColor(red: 0.44, green: 0.49, blue: 0.52, alpha: 1),
        dark: UIColor(red: 0.66, green: 0.71, blue: 0.75, alpha: 1)
    )
    static let accent = dynamic(
        light: UIColor(red: 0.72, green: 0.44, blue: 0.18, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.66, blue: 0.30, alpha: 1)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

struct ChromeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppChrome.subtitle)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppChrome.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppChrome.border, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ChromeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppChrome.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppChrome.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func chromeCard() -> some View {
        modifier(ChromeCardModifier())
    }
}
