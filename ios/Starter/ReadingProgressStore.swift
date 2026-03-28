import Foundation

struct VolumeProgress: Codable {
    var lastPage: Int
    var pagesRead: Int
    var totalPages: Int
}

@MainActor
final class ReadingProgressStore: ObservableObject {
    @Published private(set) var byVolume: [String: VolumeProgress] = [:]

    private let storageKey = "manga_reader_progress"

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

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            byVolume = try JSONDecoder().decode([String: VolumeProgress].self, from: data)
        } catch {
            byVolume = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byVolume)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Keep running if persistence fails
        }
    }
}
