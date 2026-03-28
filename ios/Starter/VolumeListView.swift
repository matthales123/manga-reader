import SwiftUI

private struct DownloadProgressState {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var label: String {
        "Downloading \(completed)/\(total)"
    }
}

struct VolumeListView: View {
    let api: MangaAPI
    let series: Series

    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore

    @State private var volumes: [Volume] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var remoteVolumeIDs: Set<String> = []
    @State private var activeDownloads: Set<String> = []
    @State private var downloadProgressByVolume: [String: DownloadProgressState] = [:]
    @State private var downloadErrors: [String: String] = [:]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading volumes...")
            } else if let errorMessage {
                ContentUnavailableView("Could not load volumes", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if volumes.isEmpty {
                ContentUnavailableView("No volumes found", systemImage: "rectangle.stack")
            } else {
                List(volumes) { volume in
                    NavigationLink {
                        ReaderView(api: api, volume: volume)
                    } label: {
                        HStack(spacing: 12) {
                            CoverThumbnailView(url: api.seriesCoverURL(series: series), title: series.title)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(volume.title)
                                    .font(.headline)

                                if let progressText = readingProgress.progressText(for: volume.id), let progress = readingProgress.progress(for: volume.id), progress.totalPages > 0 {
                                    Text(progressText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    ProgressView(value: Double(progress.pagesRead), total: Double(progress.totalPages))
                                        .tint(.orange)
                                } else {
                                    Text(volume.kind)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if offlineLibrary.isDownloaded(volumeID: volume.id) {
                                    Text("Available offline")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                if let progress = downloadProgressByVolume[volume.id], activeDownloads.contains(volume.id) {
                                    ProgressView(value: progress.fraction)
                                        .controlSize(.small)
                                        .tint(.blue)
                                    Text(progress.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let error = downloadErrors[volume.id] {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Image(systemName: trailingStatusSymbol(for: volume))
                                .font(.title3)
                                .foregroundStyle(trailingStatusColor(for: volume))
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if offlineLibrary.isDownloaded(volumeID: volume.id) {
                            Button(role: .destructive) {
                                removeOfflineCopy(for: volume)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } else if activeDownloads.contains(volume.id) {
                            Button {
                                // Keep row stable while download is active.
                            } label: {
                                Label("Downloading", systemImage: "hourglass")
                            }
                            .tint(.gray)
                            .disabled(true)
                        } else {
                            Button {
                                downloadOfflineCopy(for: volume)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(series.title)
        .task {
            await loadVolumes()
        }
        .refreshable {
            await loadVolumes()
        }
    }

    private func loadVolumes() async {
        isLoading = true
        errorMessage = nil

        do {
            let remote = try await api.fetchVolumes(seriesID: series.id)
            remoteVolumeIDs = Set(remote.map(\.id))
            volumes = mergedWithOffline(remote)
        } catch {
            let offlineOnly = offlineLibrary.downloadedVolumes(forSeriesID: series.id).map(offlineAsVolume)
            remoteVolumeIDs = []
            if offlineOnly.isEmpty {
                errorMessage = error.localizedDescription
                volumes = []
            } else {
                errorMessage = nil
                volumes = offlineOnly
            }
        }

        isLoading = false
    }

    private func downloadOfflineCopy(for volume: Volume) {
        activeDownloads.insert(volume.id)
        downloadProgressByVolume[volume.id] = DownloadProgressState(completed: 0, total: 1)
        downloadErrors[volume.id] = nil

        Task {
            defer {
                activeDownloads.remove(volume.id)
            }

            do {
                try await offlineLibrary.download(volume: volume, series: series, api: api) { completed, total in
                    downloadProgressByVolume[volume.id] = DownloadProgressState(completed: completed, total: total)
                }
                downloadProgressByVolume[volume.id] = nil
            } catch {
                downloadErrors[volume.id] = error.localizedDescription
            }
        }
    }

    private func removeOfflineCopy(for volume: Volume) {
        do {
            try offlineLibrary.removeDownload(volumeID: volume.id)
            downloadErrors[volume.id] = nil
            downloadProgressByVolume[volume.id] = nil

            // If this row exists only because of offline fallback, remove it.
            if !remoteVolumeIDs.contains(volume.id) {
                volumes.removeAll { $0.id == volume.id }
            }
        } catch {
            downloadErrors[volume.id] = error.localizedDescription
        }
    }

    private func trailingStatusSymbol(for volume: Volume) -> String {
        if activeDownloads.contains(volume.id) {
            return "arrow.down.circle.fill"
        }
        if offlineLibrary.isDownloaded(volumeID: volume.id) {
            return "checkmark.circle.fill"
        }
        return "icloud.and.arrow.down"
    }

    private func trailingStatusColor(for volume: Volume) -> Color {
        if activeDownloads.contains(volume.id) {
            return .blue
        }
        if offlineLibrary.isDownloaded(volumeID: volume.id) {
            return .green
        }
        return .secondary
    }

    private func mergedWithOffline(_ remote: [Volume]) -> [Volume] {
        var byID: [String: Volume] = [:]
        remote.forEach { byID[$0.id] = $0 }

        for offline in offlineLibrary.downloadedVolumes(forSeriesID: series.id) {
            byID[offline.id] = byID[offline.id] ?? offlineAsVolume(offline)
        }

        return byID.values.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func offlineAsVolume(_ offline: OfflineVolume) -> Volume {
        Volume(
            id: offline.id,
            title: offline.volumeTitle,
            relativePath: "offline/\(offline.id)",
            kind: offline.volumeKind,
            seriesId: offline.seriesID
        )
    }
}
