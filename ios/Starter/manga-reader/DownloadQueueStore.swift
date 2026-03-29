import Foundation
import Combine
import UserNotifications

@MainActor
final class DownloadQueueStore: ObservableObject {
    enum Status: Equatable {
        case pending
        case downloading(completed: Int, total: Int)
        case completed
        case failed(message: String)
    }

    struct QueueItem: Identifiable, Equatable {
        let id: String
        let seriesID: String
        let volumeTitle: String
        var status: Status
    }

    @Published private(set) var items: [QueueItem] = []

    private var isProcessing = false
    private var seriesByID: [String: Series] = [:]
    private weak var lastAPI: MangaAPI?
    private weak var lastOfflineLibrary: OfflineLibraryStore?

    func status(for volumeID: String) -> Status? {
        items.first(where: { $0.id == volumeID })?.status
    }

    func enqueue(volume: Volume, series: Series, api: MangaAPI, offlineLibrary: OfflineLibraryStore) {
        lastAPI = api
        lastOfflineLibrary = offlineLibrary
        seriesByID[series.id] = series

        if offlineLibrary.isDownloaded(volumeID: volume.id) {
            return
        }

        if let index = items.firstIndex(where: { $0.id == volume.id }) {
            switch items[index].status {
            case .failed:
                items[index].status = .pending
            default:
                break
            }
        } else {
            items.append(
                QueueItem(
                    id: volume.id,
                    seriesID: series.id,
                    volumeTitle: volume.title,
                    status: .pending
                )
            )
        }

        Task { await processNext() }
    }

    func removeCompleted() {
        items.removeAll {
            if case .completed = $0.status { return true }
            return false
        }
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    func retryFailed() {
        var didUpdate = false
        for index in items.indices {
            if case .failed = items[index].status {
                items[index].status = .pending
                didUpdate = true
            }
        }
        if didUpdate {
            Task { await processNext() }
        }
    }

    private func processNext() async {
        guard let api = lastAPI, let offlineLibrary = lastOfflineLibrary else { return }
        guard !isProcessing else { return }
        guard let index = items.firstIndex(where: {
            if case .pending = $0.status { return true }
            return false
        }) else {
            return
        }

        isProcessing = true
        let item = items[index]
        items[index].status = .downloading(completed: 0, total: 1)

        let series = seriesByID[item.seriesID] ?? Series(
            id: item.seriesID,
            title: item.seriesID,
            relativePath: "",
            volumeCount: 0,
            coverURL: nil
        )

        let volume = Volume(
            id: item.id,
            title: item.volumeTitle,
            relativePath: "",
            kind: "chapter",
            seriesId: item.seriesID
        )

        do {
            try await offlineLibrary.download(volume: volume, series: series, api: api) { [weak self] completed, total in
                guard let self else { return }
                if let progressIndex = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[progressIndex].status = .downloading(completed: completed, total: total)
                }
            }
            if let doneIndex = items.firstIndex(where: { $0.id == item.id }) {
                items[doneIndex].status = .completed
            }
            postLocalNotification(
                title: "Download complete",
                body: "\(item.volumeTitle) is available offline."
            )
        } catch {
            if let failIndex = items.firstIndex(where: { $0.id == item.id }) {
                let message = api.userFacingErrorMessage(for: error)
                items[failIndex].status = .failed(message: message)
                postLocalNotification(
                    title: "Download failed",
                    body: "\(item.volumeTitle): \(message)"
                )
            }
        }

        isProcessing = false
        await processNext()
    }

    private func postLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
