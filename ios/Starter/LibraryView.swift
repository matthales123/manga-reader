import SwiftUI

struct LibraryView: View {
    let api: MangaAPI

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore

    @State private var series: [Series] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading library...")
                } else if let errorMessage {
                    ContentUnavailableView("Could not load library", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if series.isEmpty {
                    ContentUnavailableView("No manga found", systemImage: "books.vertical")
                } else {
                    List(series) { entry in
                        NavigationLink {
                            VolumeListView(api: api, series: entry)
                        } label: {
                            HStack(spacing: 12) {
                                CoverThumbnailView(url: api.seriesCoverURL(series: entry), title: entry.title)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.headline)
                                    Text("\(entry.volumeCount) volumes")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Manga")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                settings.selectedTheme = theme
                            } label: {
                                if settings.selectedTheme == theme {
                                    Label(theme.title, systemImage: "checkmark")
                                } else {
                                    Text(theme.title)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: settings.selectedTheme.symbolName)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadSeries()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadSeries()
            }
            .refreshable {
                await loadSeries()
            }
        }
    }

    private func loadSeries() async {
        isLoading = true
        errorMessage = nil

        do {
            let remoteSeries = try await api.fetchSeries()
            series = mergeWithOfflineSeries(remoteSeries)
        } catch {
            let offlineSeries = offlineSeriesFallback()
            if offlineSeries.isEmpty {
                errorMessage = error.localizedDescription
                series = []
            } else {
                errorMessage = nil
                series = offlineSeries
            }
        }

        isLoading = false
    }

    private func mergeWithOfflineSeries(_ remoteSeries: [Series]) -> [Series] {
        var byID: [String: Series] = [:]
        remoteSeries.forEach { byID[$0.id] = $0 }

        for offline in offlineLibrary.downloadedSeries() {
            if byID[offline.id] == nil {
                byID[offline.id] = Series(
                    id: offline.id,
                    title: offline.title,
                    relativePath: "offline/\(offline.id)",
                    volumeCount: offline.volumeCount,
                    coverURL: nil
                )
            }
        }

        return byID.values.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func offlineSeriesFallback() -> [Series] {
        offlineLibrary.downloadedSeries().map { item in
            Series(
                id: item.id,
                title: item.title,
                relativePath: "offline/\(item.id)",
                volumeCount: item.volumeCount,
                coverURL: nil
            )
        }
    }
}
