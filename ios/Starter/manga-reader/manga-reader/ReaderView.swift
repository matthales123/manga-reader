import SwiftUI
import Combine
import UIKit

private enum ReaderOfflineImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString)
    }
}

@MainActor
struct ReaderView: View {
    let api: MangaAPI
    var seriesVolumes: [Volume] = []

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore

    @State private var pages: [PageItem] = []
    @State private var localPageURLs: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPage = 0
    @State private var refreshNonce = 0
    @State private var currentVolume: Volume

    init(api: MangaAPI, volume: Volume, seriesVolumes: [Volume] = []) {
        self.api = api
        self.seriesVolumes = seriesVolumes
        _currentVolume = State(initialValue: volume)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Divider()
                .overlay(AppChrome.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !pages.isEmpty {
                readerControls
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            bottomBar
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(AppChrome.surface)
        }
        .background(AppChrome.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: currentVolume.id) {
            await loadPages()
        }
        .onChange(of: selectedPage) { _, _ in
            persistProgress()
            prefetchNearbyOfflinePages()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            persistProgress()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        }
        .onChange(of: settings.keepScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    private var header: some View {
        let sideWidth: CGFloat = 84

        return HStack(spacing: 8) {
            HStack {
                Button {
                    persistProgress()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(ChromeIconButtonStyle())

                Spacer(minLength: 0)
            }
            .frame(width: sideWidth)

            VStack(spacing: 2) {
                Text(currentVolume.title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(AppChrome.title)
                Text("\(max(pages.count, 0)) pages")
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
                    refreshNonce += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ChromeIconButtonStyle())
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading pages...")
        } else if let errorMessage {
            UnavailableStateView(title: "Could not load pages", systemImage: "exclamationmark.triangle", message: errorMessage)
                .padding(20)
        } else if pages.isEmpty {
            UnavailableStateView(title: "No pages found", systemImage: "doc")
                .padding(20)
        } else {
            TabView(selection: $selectedPage) {
                ForEach(orderedPages) { page in
                    GeometryReader { geometry in
                        let localFileURL = localFileURLForPage(page.index)
                        let localImage = localImageForPage(page.index)
                        ZoomablePageContainerView(
                            localImage: localImage,
                            remoteURL: localImage == nil
                                ? api.pageImageURL(volumeID: currentVolume.id, index: page.index, cacheBuster: refreshNonce)
                                : nil,
                            mode: settings.readerZoomMode,
                            showDebugOverlay: settings.showReaderDebugOverlay,
                            debugPageIndex: page.index,
                            debugLocalPath: localFileURL?.lastPathComponent,
                            debugLocalFileExists: localFileURL != nil,
                            debugLocalDecoded: localImage != nil
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var readerControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    moveToPreviousChapter()
                } label: {
                    Label("Prev Chapter", systemImage: "backward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .disabled(previousChapter == nil)
                .background(buttonBackground)

                Menu {
                    ForEach(chapterVolumes) { chapter in
                        Button {
                            openChapter(chapter)
                        } label: {
                            if chapter.id == currentVolume.id {
                                Label(chapter.title, systemImage: "checkmark")
                            } else {
                                Text(chapter.title)
                            }
                        }
                    }
                } label: {
                    Label("Chapter", systemImage: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .background(buttonBackground)

                Button {
                    moveToNextChapter()
                } label: {
                    Label("Next Chapter", systemImage: "forward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .disabled(nextChapter == nil)
                .background(buttonBackground)
            }

            HStack(spacing: 10) {
                Button {
                    moveToPreviousPage()
                } label: {
                    Text("Previous")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .disabled(settings.readerDirection == .rightToLeft ? selectedPage >= pages.count - 1 : selectedPage <= 0)
                .background(buttonBackground)

                Text("Page \(selectedPage + 1) / \(pages.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppChrome.subtitle)
                    .frame(minWidth: 90)

                Button {
                    moveToNextPage()
                } label: {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .disabled(settings.readerDirection == .rightToLeft ? selectedPage <= 0 : selectedPage >= pages.count - 1)
                .background(buttonBackground)
            }
        }
        .foregroundStyle(AppChrome.title)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppChrome.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppChrome.border, lineWidth: 1)
            )
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text("Library")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppChrome.subtitle.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppChrome.border, lineWidth: 1)
                )

            Text("Reader")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppChrome.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppChrome.accent.opacity(0.45), lineWidth: 1)
                )
        }
    }

    private func loadPages() async {
        isLoading = true
        errorMessage = nil

        if let offlinePages = offlineLibrary.offlinePages(for: currentVolume.id), !offlinePages.isEmpty {
            readingProgress.markOpened(seriesID: currentVolume.seriesId, volumeID: currentVolume.id, volumeTitle: currentVolume.title)
            localPageURLs = offlinePages
            pages = offlinePages.enumerated().map { idx, pageURL in
                PageItem(index: idx, name: pageURL.lastPathComponent, url: pageURL.absoluteString)
            }
            selectedPage = readingProgress.startPageIndex(for: currentVolume.id, totalPages: pages.count)
            persistProgress()
            prefetchNearbyOfflinePages()
            isLoading = false
            return
        }

        localPageURLs = []

        do {
            readingProgress.markOpened(seriesID: currentVolume.seriesId, volumeID: currentVolume.id, volumeTitle: currentVolume.title)
            pages = try await api.fetchPages(volumeID: currentVolume.id)
            selectedPage = readingProgress.startPageIndex(for: currentVolume.id, totalPages: pages.count)
            persistProgress()
        } catch {
            errorMessage = api.userFacingErrorMessage(for: error)
            pages = []
        }

        isLoading = false
    }

    private func persistProgress() {
        guard !pages.isEmpty else {
            return
        }

        readingProgress.markRead(volumeID: currentVolume.id, pageIndex: selectedPage, totalPages: pages.count)
    }

    private func localImageForPage(_ index: Int) -> UIImage? {
        guard index >= 0, index < localPageURLs.count else {
            return nil
        }
        let url = localPageURLs[index]

        if let cached = ReaderOfflineImageCache.image(for: url) {
            return cached
        }

        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        ReaderOfflineImageCache.store(image, for: url)
        return image
    }

    private func localFileURLForPage(_ index: Int) -> URL? {
        guard index >= 0, index < localPageURLs.count else {
            return nil
        }
        return localPageURLs[index]
    }

    private func prefetchNearbyOfflinePages() {
        guard !localPageURLs.isEmpty else { return }

        let start = max(selectedPage - 3, 0)
        let end = min(selectedPage + 3, localPageURLs.count - 1)
        let urls = Array(localPageURLs[start...end])

        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                if ReaderOfflineImageCache.image(for: url) != nil {
                    continue
                }
                if let image = UIImage(contentsOfFile: url.path) {
                    ReaderOfflineImageCache.store(image, for: url)
                }
            }
        }
    }

    private var orderedPages: [PageItem] {
        if settings.readerDirection == .rightToLeft {
            return pages.sorted { $0.index > $1.index }
        }
        return pages.sorted { $0.index < $1.index }
    }

    private func moveToPreviousPage() {
        if settings.readerDirection == .rightToLeft {
            selectedPage = min(selectedPage + 1, max(pages.count - 1, 0))
        } else {
            selectedPage = max(selectedPage - 1, 0)
        }
    }

    private func moveToNextPage() {
        if settings.readerDirection == .rightToLeft {
            selectedPage = max(selectedPage - 1, 0)
        } else {
            selectedPage = min(selectedPage + 1, max(pages.count - 1, 0))
        }
    }

    private var chapterVolumes: [Volume] {
        var byID: [String: Volume] = [:]
        seriesVolumes.forEach { byID[$0.id] = $0 }
        byID[currentVolume.id] = byID[currentVolume.id] ?? currentVolume
        return byID.values.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private var currentChapterIndex: Int? {
        chapterVolumes.firstIndex(where: { $0.id == currentVolume.id })
    }

    private var previousChapter: Volume? {
        guard let currentChapterIndex, currentChapterIndex > 0 else { return nil }
        return chapterVolumes[currentChapterIndex - 1]
    }

    private var nextChapter: Volume? {
        guard let currentChapterIndex, currentChapterIndex < chapterVolumes.count - 1 else { return nil }
        return chapterVolumes[currentChapterIndex + 1]
    }

    private func openChapter(_ chapter: Volume) {
        guard chapter.id != currentVolume.id else { return }
        persistProgress()
        currentVolume = chapter
        pages = []
        localPageURLs = []
        selectedPage = 0
        errorMessage = nil
        refreshNonce += 1
    }

    private func moveToPreviousChapter() {
        guard let chapter = previousChapter else { return }
        openChapter(chapter)
    }

    private func moveToNextChapter() {
        guard let chapter = nextChapter else { return }
        openChapter(chapter)
    }
}
