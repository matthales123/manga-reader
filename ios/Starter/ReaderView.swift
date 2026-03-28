import SwiftUI
import UIKit

struct ReaderView: View {
    let api: MangaAPI
    let volume: Volume

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var readingProgress: ReadingProgressStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore

    @State private var pages: [PageItem] = []
    @State private var localPageURLs: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPage = 0
    @State private var refreshNonce = 0

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pages...")
            } else if let errorMessage {
                ContentUnavailableView("Could not load pages", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if pages.isEmpty {
                ContentUnavailableView("No pages found", systemImage: "doc")
            } else {
                TabView(selection: $selectedPage) {
                    ForEach(pages) { page in
                        GeometryReader { geometry in
                            ScrollView([.horizontal, .vertical]) {
                                pageImageView(for: page, geometry: geometry)
                            }
                        }
                        .tag(page.index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .navigationTitle(volume.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    persistProgress()
                    dismiss()
                } label: {
                    Label("Volumes", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshNonce += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadPages()
        }
        .onChange(of: selectedPage) { _, _ in
            persistProgress()
        }
        .onDisappear {
            persistProgress()
        }
    }

    private func loadPages() async {
        isLoading = true
        errorMessage = nil

        if let offlinePages = offlineLibrary.offlinePages(for: volume.id), !offlinePages.isEmpty {
            localPageURLs = offlinePages
            pages = offlinePages.enumerated().map { idx, pageURL in
                PageItem(index: idx, name: pageURL.lastPathComponent, url: pageURL.absoluteString)
            }
            selectedPage = readingProgress.startPageIndex(for: volume.id, totalPages: pages.count)
            persistProgress()
            isLoading = false
            return
        }

        localPageURLs = []

        do {
            pages = try await api.fetchPages(volumeID: volume.id)
            selectedPage = readingProgress.startPageIndex(for: volume.id, totalPages: pages.count)
            persistProgress()
        } catch {
            errorMessage = error.localizedDescription
            pages = []
        }

        isLoading = false
    }

    private func persistProgress() {
        guard !pages.isEmpty else {
            return
        }

        readingProgress.markRead(volumeID: volume.id, pageIndex: selectedPage, totalPages: pages.count)
    }

    @ViewBuilder
    private func pageImageView(for page: PageItem, geometry: GeometryProxy) -> some View {
        if let localImage = localImageForPage(page.index) {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: geometry.size.width)
        } else {
            AsyncImage(url: api.pageImageURL(volumeID: volume.id, index: page.index, cacheBuster: refreshNonce)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: geometry.size.width)
                case .failure:
                    ContentUnavailableView("Image failed", systemImage: "xmark.octagon")
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private func localImageForPage(_ index: Int) -> UIImage? {
        guard index >= 0, index < localPageURLs.count else {
            return nil
        }
        return UIImage(contentsOfFile: localPageURLs[index].path)
    }
}
