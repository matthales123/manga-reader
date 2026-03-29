import SwiftUI
import Combine

private enum VolumeSortOption: String, CaseIterable, Identifiable {
    case title
    case downloadedFirst
    case progressFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .downloadedFirst: return "Downloaded First"
        case .progressFirst: return "Progress First"
        }
    }
}

private struct ArcSection: Identifiable {
    let id: String
    let title: String
    let volumes: [Volume]
}

@MainActor
struct VolumeListView: View {
    let api: MangaAPI
    let series: Series
    var focusedVolumeID: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @EnvironmentObject private var downloadQueue: DownloadQueueStore

    @State private var volumes: [Volume] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var remoteVolumeIDs: Set<String> = []
    @State private var scrollTargetID: String?
    @State private var resolvedArcs: [StoryArc] = []

    @State private var searchText = ""
    @State private var downloadedOnly = false
    @State private var sortOption: VolumeSortOption = .title

    var body: some View {
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
            scrollTargetID = focusedVolumeID ?? readingProgress.lastOpenedVolumeID(for: series.id)
            await loadVolumes()
            await loadArcs()
        }
        .refreshable {
            await loadVolumes()
            await loadArcs()
        }
        .onAppear {
            if focusedVolumeID == nil {
                scrollTargetID = readingProgress.lastOpenedVolumeID(for: series.id)
            }
        }
    }

    private var header: some View {
        let sideWidth: CGFloat = 84

        return HStack(spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(ChromeIconButtonStyle())

                Spacer(minLength: 0)
            }
            .frame(width: sideWidth)

            VStack(spacing: 2) {
                Text(series.title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(AppChrome.title)
                Text("\(displayVolumes.count) volumes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppChrome.subtitle)
            }
            .frame(maxWidth: .infinity)

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
                    Task {
                        await loadVolumes()
                        await loadArcs()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ChromeIconButtonStyle())
                .disabled(isLoading)
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppChrome.subtitle)
                TextField("Search volumes", text: $searchText)
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
                    downloadedOnly.toggle()
                } label: {
                    Label("Downloaded", systemImage: downloadedOnly ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(downloadedOnly ? .green : .gray)

                Spacer()

                Menu {
                    ForEach(VolumeSortOption.allCases) { option in
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
            ProgressView("Loading volumes...")
        } else if let errorMessage {
            UnavailableStateView(title: "Could not load volumes", systemImage: "exclamationmark.triangle", message: errorMessage)
                .padding(20)
        } else if displayVolumes.isEmpty {
            UnavailableStateView(title: "No volumes found", systemImage: "rectangle.stack")
                .padding(20)
        } else {
            VStack(spacing: 0) {
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating volumes...")
                            .font(.caption)
                            .foregroundStyle(AppChrome.subtitle)
                    }
                    .padding(.top, 8)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(arcSections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppChrome.subtitle)
                                        .padding(.horizontal, 4)

                                    ForEach(section.volumes) { volume in
                                        HStack(spacing: 12) {
                                            NavigationLink {
                                                ReaderView(api: api, volume: volume, seriesVolumes: volumes)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    CoverThumbnailView(url: api.seriesCoverURL(series: series), title: series.title)

                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(volume.title)
                                                            .font(.system(size: 16, weight: .bold))
                                                            .lineLimit(1)
                                                            .foregroundStyle(AppChrome.title)

                                                        if let progressText = readingProgress.progressText(for: volume.id), let progress = readingProgress.progress(for: volume.id), progress.totalPages > 0 {
                                                            Text(progressText)
                                                                .font(.system(size: 14, weight: .medium))
                                                                .foregroundStyle(AppChrome.subtitle)
                                                        } else {
                                                            Text(volume.kind)
                                                                .font(.system(size: 14, weight: .medium))
                                                                .foregroundStyle(AppChrome.subtitle)
                                                        }

                                                        if let queueText = queueStatusText(for: volume.id) {
                                                            Text(queueText)
                                                                .font(.caption)
                                                                .foregroundStyle(AppChrome.subtitle)
                                                        }
                                                    }

                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .simultaneousGesture(TapGesture().onEnded {
                                                readingProgress.markOpened(seriesID: series.id, volumeID: volume.id, volumeTitle: volume.title)
                                            })

                                            VStack(spacing: 8) {
                                                Image(systemName: trailingStatusSymbol(for: volume))
                                                    .font(.title3)
                                                    .foregroundStyle(trailingStatusColor(for: volume))

                                                volumeActionButton(for: volume)
                                            }
                                        }
                                        .padding(12)
                                        .chromeCard()
                                        .id(volume.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        scrollToTarget(proxy)
                    }
                    .onChange(of: scrollTargetID) { _, _ in
                        scrollToTarget(proxy)
                    }
                }
            }
        }
    }

    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let target = scrollTargetID,
              displayVolumes.contains(where: { $0.id == target })
        else { return }

        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(target, anchor: .center)
            }
        }
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

    private var displayVolumes: [Volume] {
        var items = volumes

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            items = items.filter { $0.title.lowercased().contains(q) }
        }

        if downloadedOnly {
            items = items.filter { offlineLibrary.isDownloaded(volumeID: $0.id) }
        }

        switch sortOption {
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .downloadedFirst:
            items.sort { lhs, rhs in
                let l = offlineLibrary.isDownloaded(volumeID: lhs.id)
                let r = offlineLibrary.isDownloaded(volumeID: rhs.id)
                if l == r {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return l && !r
            }
        case .progressFirst:
            items.sort { lhs, rhs in
                let lp = readingProgress.progress(for: lhs.id)?.pagesRead ?? 0
                let rp = readingProgress.progress(for: rhs.id)?.pagesRead ?? 0
                if lp == rp {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lp > rp
            }
        }

        return items
    }

    private var arcSections: [ArcSection] {
        let resolved = sectionsFromResolvedArcs()
        if !resolved.isEmpty {
            return resolved
        }

        var grouped: [String: [Volume]] = [:]
        var orderedKeys: [String] = []

        for volume in displayVolumes {
            let key = inferredArcName(for: volume) ?? "Other Chapters"
            if grouped[key] == nil {
                grouped[key] = []
                orderedKeys.append(key)
            }
            grouped[key]?.append(volume)
        }

        return orderedKeys.map { key in
            ArcSection(id: key, title: key, volumes: grouped[key] ?? [])
        }
    }

    private func inferredArcName(for volume: Volume) -> String? {
        let path = volume.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let components = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }

        guard components.count >= 2 else { return nil }

        let candidate = components[max(components.count - 2, 0)]
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else { return nil }

        let normalizedCandidate = candidate.lowercased()
        let normalizedTitle = volume.title.lowercased()
        if normalizedCandidate == normalizedTitle || normalizedCandidate == volume.id.lowercased() {
            return nil
        }

        if normalizedCandidate == "offline" {
            return "Downloaded"
        }

        return candidate
    }

    private func sectionsFromResolvedArcs() -> [ArcSection] {
        guard !resolvedArcs.isEmpty else { return [] }
        guard displayVolumes.count > 0 else { return [] }

        let sortedArcs = resolvedArcs.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return (lhs.order ?? Int.max) < (rhs.order ?? Int.max)
            }
            let ls = lhs.startChapter ?? -Double.greatestFiniteMagnitude
            let rs = rhs.startChapter ?? -Double.greatestFiniteMagnitude
            if ls != rs { return ls < rs }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        var sections: [ArcSection] = []
        var assigned = Set<String>()

        for arc in sortedArcs {
            var matches: [Volume] = []
            for volume in displayVolumes where !assigned.contains(volume.id) {
                guard let chapter = chapterNumber(for: volume) else { continue }
                if isChapter(chapter, inside: arc) {
                    matches.append(volume)
                }
            }

            guard !matches.isEmpty else { continue }
            matches.forEach { assigned.insert($0.id) }
            sections.append(ArcSection(id: arc.id, title: arc.name, volumes: matches))
        }

        let unassigned = displayVolumes.filter { !assigned.contains($0.id) }
        if !unassigned.isEmpty {
            sections.append(ArcSection(id: "unassigned", title: "Other Chapters", volumes: unassigned))
        }

        return sections
    }

    private func isChapter(_ chapter: Double, inside arc: StoryArc) -> Bool {
        if let start = arc.startChapter, chapter < start { return false }
        if let end = arc.endChapter, chapter > end { return false }
        return true
    }

    private func chapterNumber(for volume: Volume) -> Double? {
        if let fromTitle = firstDecimal(in: volume.title) {
            return fromTitle
        }

        let path = volume.relativePath
            .split(separator: "/")
            .last
            .map(String.init) ?? volume.relativePath
        return firstDecimal(in: path)
    }

    private func firstDecimal(in text: String) -> Double? {
        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text)
        else {
            return nil
        }
        return Double(text[swiftRange])
    }

    private func loadVolumes() async {
        if volumes.isEmpty {
            let cached = LibraryCacheStore.loadVolumes(seriesID: series.id)
            if !cached.isEmpty {
                volumes = mergedWithOffline(cached)
            }
        }

        let hasExisting = !volumes.isEmpty
        isLoading = !hasExisting
        isRefreshing = hasExisting
        errorMessage = nil

        do {
            let remote = try await api.fetchVolumes(seriesID: series.id)
            remoteVolumeIDs = Set(remote.map(\.id))
            let merged = mergedWithOffline(remote)
            volumes = merged
            LibraryCacheStore.saveVolumes(seriesID: series.id, volumes: merged)
        } catch {
            let offlineOnly = offlineLibrary.downloadedVolumes(forSeriesID: series.id).map(offlineAsVolume)
            remoteVolumeIDs = []
            if offlineOnly.isEmpty {
                if !hasExisting {
                    errorMessage = api.userFacingErrorMessage(for: error)
                    volumes = []
                }
            } else {
                errorMessage = nil
                volumes = offlineOnly
                LibraryCacheStore.saveVolumes(seriesID: series.id, volumes: offlineOnly)
            }
        }

        isLoading = false
        isRefreshing = false

        if focusedVolumeID == nil {
            scrollTargetID = readingProgress.lastOpenedVolumeID(for: series.id)
        }
    }

    private func loadArcs() async {
        if resolvedArcs.isEmpty {
            let cached = LibraryCacheStore.loadArcs(seriesID: series.id)
            if !cached.isEmpty {
                resolvedArcs = cached
            }
        }

        do {
            let remoteArcs = try await api.fetchStoryArcs(seriesID: series.id)
            if !remoteArcs.isEmpty {
                resolvedArcs = remoteArcs
                LibraryCacheStore.saveArcs(seriesID: series.id, arcs: remoteArcs)
            }
        } catch {
            // Keep cached arcs when endpoint is unavailable.
        }
    }

    private func trailingStatusSymbol(for volume: Volume) -> String {
        switch downloadQueue.status(for: volume.id) {
        case .pending:
            return "clock"
        case .downloading:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case nil:
            if offlineLibrary.isDownloaded(volumeID: volume.id) {
                return "checkmark.circle.fill"
            }
            return "icloud.and.arrow.down"
        }
    }

    private func trailingStatusColor(for volume: Volume) -> Color {
        switch downloadQueue.status(for: volume.id) {
        case .pending:
            return .orange
        case .downloading:
            return .blue
        case .failed:
            return .red
        case .completed:
            return .green
        case nil:
            if offlineLibrary.isDownloaded(volumeID: volume.id) {
                return .green
            }
            return .secondary
        }
    }

    private func queueStatusText(for volumeID: String) -> String? {
        switch downloadQueue.status(for: volumeID) {
        case .pending:
            return "Queued"
        case .downloading(let completed, let total):
            return "Downloading \(completed)/\(total)"
        case .failed(let message):
            return message
        case .completed:
            return "Download complete"
        case nil:
            return nil
        }
    }

    @ViewBuilder
    private func volumeActionButton(for volume: Volume) -> some View {
        switch downloadQueue.status(for: volume.id) {
        case .pending:
            Label("Queued", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(AppChrome.subtitle)
        case .downloading:
            Label("Downloading", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(AppChrome.subtitle)
        case .failed:
            Button {
                downloadQueue.enqueue(volume: volume, series: series, api: api, offlineLibrary: offlineLibrary)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        case .completed:
            if offlineLibrary.isDownloaded(volumeID: volume.id) {
                Button(role: .destructive) {
                    try? offlineLibrary.removeDownload(volumeID: volume.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        case nil:
            if offlineLibrary.isDownloaded(volumeID: volume.id) {
                Button(role: .destructive) {
                    try? offlineLibrary.removeDownload(volumeID: volume.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button {
                    downloadQueue.enqueue(volume: volume, series: series, api: api, offlineLibrary: offlineLibrary)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
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
