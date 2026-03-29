import SwiftUI
import Combine

private enum LibrarySortOption: String, CaseIterable, Identifiable {
    case title
    case mostVolumes
    case favoritesFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .mostVolumes: return "Most Volumes"
        case .favoritesFirst: return "Favorites First"
        }
    }
}

@MainActor
struct LibraryView: View {
    let api: MangaAPI

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @EnvironmentObject private var downloadQueue: DownloadQueueStore

    @State private var series: [Series] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingSettings = false

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var sortOption: LibrarySortOption = .title
    @State private var selectedCollectionName: String? = nil

    @State private var resumeTarget: ContinueReadingDestination?
    @State private var selectedSeriesForCollections: Series?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                searchAndFilters
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                Divider()
                    .overlay(AppChrome.border)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(AppChrome.surface)
            }
            .background(AppChrome.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadSeries()
            }
            .refreshable {
                await loadSeries()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(readingProgress)
                    .environmentObject(offlineLibrary)
                    .environmentObject(downloadQueue)
            }
            .sheet(item: $selectedSeriesForCollections) { series in
                collectionAssignmentSheet(for: series)
            }
            .navigationDestination(item: $resumeTarget) { target in
                ReaderView(api: api, volume: target.volume, seriesVolumes: target.seriesVolumes)
            }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Manga")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(AppChrome.title)
                Text(filteredSeries.isEmpty ? "Library" : "\(filteredSeries.count) series")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppChrome.subtitle)
            }

            HStack {
                Spacer()

                HStack(spacing: 8) {
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
                    .buttonStyle(ChromeIconButtonStyle())

                    Button {
                        Task { await loadSeries() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ChromeIconButtonStyle())
                    .disabled(isLoading)

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(ChromeIconButtonStyle())
                }
            }
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppChrome.subtitle)
                TextField("Search series", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppChrome.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppChrome.border, lineWidth: 1)
                    )
            )

            HStack(spacing: 8) {
                Button {
                    showFavoritesOnly.toggle()
                } label: {
                    Label("Favorites", systemImage: showFavoritesOnly ? "star.fill" : "star")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(showFavoritesOnly ? .yellow : .gray)

                Spacer()

                Menu {
                    Button {
                        selectedCollectionName = nil
                    } label: {
                        if selectedCollectionName == nil {
                            Label("All Collections", systemImage: "checkmark")
                        } else {
                            Text("All Collections")
                        }
                    }

                    ForEach(settings.collectionNames, id: \.self) { name in
                        Button {
                            selectedCollectionName = name
                        } label: {
                            if selectedCollectionName == name {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    Label(selectedCollectionName ?? "Collections", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Menu {
                    ForEach(LibrarySortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading library...")
        } else if let errorMessage {
            UnavailableStateView(title: "Could not load library", systemImage: "exclamationmark.triangle", message: errorMessage)
                .padding(20)
        } else if filteredSeries.isEmpty {
            UnavailableStateView(title: "No manga found", systemImage: "books.vertical")
                .padding(20)
        } else {
            VStack(spacing: 0) {
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating library...")
                            .font(.caption)
                            .foregroundStyle(AppChrome.subtitle)
                    }
                    .padding(.top, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let card = continueReadingCard {
                            continueReadingSection(card)
                        }

                        ForEach(filteredSeries) { entry in
                            NavigationLink {
                                VolumeListView(api: api, series: entry)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverThumbnailView(url: api.seriesCoverURL(series: entry), title: entry.title)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.system(size: 16, weight: .bold))
                                            .lineLimit(1)
                                            .foregroundStyle(AppChrome.title)
                                        Text("\(entry.volumeCount) volumes")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppChrome.subtitle)
                                    }

                                    Spacer()

                                    Button {
                                        settings.toggleFavoriteSeries(entry.id)
                                    } label: {
                                        Image(systemName: settings.isFavoriteSeries(entry.id) ? "star.fill" : "star")
                                            .foregroundStyle(settings.isFavoriteSeries(entry.id) ? .yellow : AppChrome.subtitle)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        selectedSeriesForCollections = entry
                                    } label: {
                                        Image(systemName: "folder.badge.plus")
                                            .foregroundStyle(AppChrome.subtitle)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .chromeCard()
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    settings.toggleFavoriteSeries(entry.id)
                                } label: {
                                    Label(
                                        settings.isFavoriteSeries(entry.id) ? "Remove Favorite" : "Add Favorite",
                                        systemImage: settings.isFavoriteSeries(entry.id) ? "star.slash" : "star"
                                    )
                                }

                                if settings.collectionNames.isEmpty {
                                    Text("No collections yet (create in Settings)")
                                } else {
                                    Menu("Collections") {
                                        ForEach(settings.collectionNames, id: \.self) { name in
                                            Button {
                                                settings.toggleSeries(entry.id, inCollection: name)
                                            } label: {
                                                if settings.isSeries(entry.id, inCollection: name) {
                                                    Label(name, systemImage: "checkmark")
                                                } else {
                                                    Text(name)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func continueReadingSection(_ card: ContinueReadingCard) -> some View {
        Button {
            resumeTarget = card.destination
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "book.fill")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(AppChrome.accent))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue Reading")
                        .font(.caption)
                        .foregroundStyle(AppChrome.subtitle)
                    Text(card.series.title)
                        .font(.headline)
                        .foregroundStyle(AppChrome.title)
                    Text("\(card.volumeTitle) • Page \(card.pageNumber)")
                        .font(.subheadline)
                        .foregroundStyle(AppChrome.subtitle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(AppChrome.subtitle)
            }
            .padding(12)
            .chromeCard()
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text("Library")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppChrome.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppChrome.accent.opacity(0.45), lineWidth: 1)
                )

            Text("Reader")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppChrome.subtitle.opacity(0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppChrome.border, lineWidth: 1)
                )
        }
    }

    private var filteredSeries: [Series] {
        var items = series

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            items = items.filter { $0.title.lowercased().contains(q) }
        }

        if showFavoritesOnly {
            items = items.filter { settings.isFavoriteSeries($0.id) }
        }

        if let selectedCollectionName {
            items = items.filter { settings.isSeries($0.id, inCollection: selectedCollectionName) }
        }

        switch sortOption {
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .mostVolumes:
            items.sort { lhs, rhs in
                if lhs.volumeCount == rhs.volumeCount {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.volumeCount > rhs.volumeCount
            }
        case .favoritesFirst:
            items.sort { lhs, rhs in
                let l = settings.isFavoriteSeries(lhs.id)
                let r = settings.isFavoriteSeries(rhs.id)
                if l == r {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return l && !r
            }
        }

        return items
    }

    private func loadSeries() async {
        if series.isEmpty {
            let cached = LibraryCacheStore.loadSeries()
            if !cached.isEmpty {
                series = mergeWithOfflineSeries(cached)
            }
        }

        let hasExisting = !series.isEmpty
        isLoading = !hasExisting
        isRefreshing = hasExisting
        errorMessage = nil

        do {
            let remoteSeries = try await api.fetchSeries()
            let merged = mergeWithOfflineSeries(remoteSeries)
            series = merged
            LibraryCacheStore.saveSeries(merged)
        } catch {
            let offlineSeries = offlineSeriesFallback()
            if offlineSeries.isEmpty {
                if !hasExisting {
                    errorMessage = api.userFacingErrorMessage(for: error)
                    series = []
                }
            } else {
                errorMessage = nil
                series = offlineSeries
                LibraryCacheStore.saveSeries(offlineSeries)
            }
        }

        isLoading = false
        isRefreshing = false
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

    private var continueReadingCard: ContinueReadingCard? {
        guard let seriesID = readingProgress.lastOpenedSeriesID,
              let volumeID = readingProgress.lastOpenedVolumeID,
              let seriesMatch = series.first(where: { $0.id == seriesID })
        else {
            return nil
        }

        let allSeriesVolumes = resumeVolumes(for: seriesMatch)
        let resumeVolume = allSeriesVolumes.first(where: { $0.id == volumeID }) ?? Volume(
            id: volumeID,
            title: readingProgress.lastOpenedVolumeTitle ?? "Resume",
            relativePath: "",
            kind: "chapter",
            seriesId: seriesID
        )

        return ContinueReadingCard(
            series: seriesMatch,
            volumeTitle: readingProgress.lastOpenedVolumeTitle ?? resumeVolume.title,
            pageNumber: readingProgress.progress(for: volumeID)?.lastPage ?? 1,
            destination: ContinueReadingDestination(
                series: seriesMatch,
                volume: resumeVolume,
                seriesVolumes: allSeriesVolumes
            )
        )
    }

    private func resumeVolumes(for series: Series) -> [Volume] {
        let cached = LibraryCacheStore.loadVolumes(seriesID: series.id)
        let offline = offlineLibrary.downloadedVolumes(forSeriesID: series.id).map(offlineAsVolume)

        var byID: [String: Volume] = [:]
        cached.forEach { byID[$0.id] = $0 }
        offline.forEach { byID[$0.id] = byID[$0.id] ?? $0 }

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

    private func collectionAssignmentSheet(for series: Series) -> some View {
        NavigationStack {
            List {
                if settings.collectionNames.isEmpty {
                    Text("No collections yet. Create one in Settings.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.collectionNames, id: \.self) { name in
                        Button {
                            settings.toggleSeries(series.id, inCollection: name)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if settings.isSeries(series.id, inCollection: name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppChrome.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(series.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selectedSeriesForCollections = nil }
                }
            }
        }
    }
}

private struct ContinueReadingCard {
    let series: Series
    let volumeTitle: String
    let pageNumber: Int
    let destination: ContinueReadingDestination
}

private struct ContinueReadingDestination: Identifiable, Hashable {
    let series: Series
    let volume: Volume
    let seriesVolumes: [Volume]

    var id: String { volume.id }
}
