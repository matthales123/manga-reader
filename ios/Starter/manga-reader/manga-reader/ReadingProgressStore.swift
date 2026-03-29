import Foundation
import Combine

struct VolumeProgress: Codable {
    var lastPage: Int
    var pagesRead: Int
    var totalPages: Int
}

@MainActor
final class ReadingProgressStore: ObservableObject {
    @Published private(set) var byVolume: [String: VolumeProgress] = [:]
    @Published private(set) var lastOpenedVolumeBySeries: [String: String] = [:]
    @Published private(set) var lastOpenedSeriesID: String?
    @Published private(set) var lastOpenedVolumeID: String?
    @Published private(set) var lastOpenedVolumeTitle: String?

    private let storageKey = "manga_reader_progress"
    private let lastOpenedBySeriesKey = "manga_reader_last_opened_by_series"
    private let lastOpenedSeriesIDKey = "manga_reader_last_opened_series_id"
    private let lastOpenedVolumeIDKey = "manga_reader_last_opened_volume_id"
    private let lastOpenedVolumeTitleKey = "manga_reader_last_opened_volume_title"

    init() {
        load()
    }

    func markRead(volumeID: String, pageIndex: Int, totalPages: Int) {
        let current = byVolume[volumeID] ?? VolumeProgress(lastPage: 1, pagesRead: 0, totalPages: totalPages)
        let oneBasedPage = max(pageIndex + 1, 1)

        byVolume[volumeID] = VolumeProgress(
            lastPage: oneBasedPage,
            pagesRead: max(current.pagesRead, oneBasedPage),
            totalPages: max(totalPages, current.totalPages)
        )
        save()
    }

    func progress(for volumeID: String) -> VolumeProgress? {
        byVolume[volumeID]
    }

    func markOpened(seriesID: String, volumeID: String, volumeTitle: String) {
        lastOpenedVolumeBySeries[seriesID] = volumeID
        lastOpenedSeriesID = seriesID
        lastOpenedVolumeID = volumeID
        lastOpenedVolumeTitle = volumeTitle
        saveLastOpened()
    }

    func lastOpenedVolumeID(for seriesID: String) -> String? {
        lastOpenedVolumeBySeries[seriesID]
    }

    func progressText(for volumeID: String) -> String? {
        guard let progress = byVolume[volumeID], progress.totalPages > 0 else {
            return nil
        }

        if progress.pagesRead >= progress.totalPages {
            return "Complete (\(progress.totalPages)/\(progress.totalPages))"
        }

        return "Read \(progress.pagesRead)/\(progress.totalPages)"
    }

    func startPageIndex(for volumeID: String, totalPages: Int) -> Int {
        guard let progress = byVolume[volumeID] else {
            return 0
        }

        return min(max(progress.lastPage - 1, 0), max(totalPages - 1, 0))
    }

    func exportJSONString() -> String? {
        do {
            let data = try JSONEncoder().encode(byVolume)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func importFromJSONString(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else {
            return false
        }
        do {
            byVolume = try JSONDecoder().decode([String: VolumeProgress].self, from: data)
            save()
            return true
        } catch {
            return false
        }
    }

    func clearAllProgress() {
        byVolume = [:]
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            byVolume = try JSONDecoder().decode([String: VolumeProgress].self, from: data)
        } catch {
            byVolume = [:]
        }

        if let raw = UserDefaults.standard.dictionary(forKey: lastOpenedBySeriesKey) as? [String: String] {
            lastOpenedVolumeBySeries = raw
        }
        lastOpenedSeriesID = UserDefaults.standard.string(forKey: lastOpenedSeriesIDKey)
        lastOpenedVolumeID = UserDefaults.standard.string(forKey: lastOpenedVolumeIDKey)
        lastOpenedVolumeTitle = UserDefaults.standard.string(forKey: lastOpenedVolumeTitleKey)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byVolume)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Keep running if persistence fails
        }
    }

    private func saveLastOpened() {
        UserDefaults.standard.set(lastOpenedVolumeBySeries, forKey: lastOpenedBySeriesKey)
        UserDefaults.standard.set(lastOpenedSeriesID, forKey: lastOpenedSeriesIDKey)
        UserDefaults.standard.set(lastOpenedVolumeID, forKey: lastOpenedVolumeIDKey)
        UserDefaults.standard.set(lastOpenedVolumeTitle, forKey: lastOpenedVolumeTitleKey)
    }
}
