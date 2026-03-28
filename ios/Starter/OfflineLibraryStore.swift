import Foundation
import UniformTypeIdentifiers

struct OfflineVolume: Identifiable {
    let id: String
    let volumeTitle: String
    let volumeKind: String
    let seriesID: String
    let seriesTitle: String
    let downloadedAt: Date
    let pageURLs: [URL]
}

struct OfflineSeriesSummary: Identifiable {
    let id: String
    let title: String
    let volumeCount: Int
}

private struct OfflineVolumeManifest: Codable {
    let version: Int
    let volumeID: String
    let volumeTitle: String
    let volumeKind: String
    let seriesID: String
    let seriesTitle: String
    let downloadedAt: Date
    let pageFiles: [String]
}

enum OfflineLibraryError: LocalizedError {
    case noPages
    case invalidPageURL
    case responseError

    var errorDescription: String? {
        switch self {
        case .noPages:
            return "This volume has no pages to download."
        case .invalidPageURL:
            return "A page URL from the server was invalid."
        case .responseError:
            return "A page download failed."
        }
    }
}

@MainActor
final class OfflineLibraryStore: ObservableObject {
    @Published private(set) var downloadedByID: [String: OfflineVolume] = [:]

    private let fileManager = FileManager.default
    private let rootURL: URL

    init() {
        rootURL = Self.makeRootURL()
        createRootDirectoryIfNeeded()
        reload()
    }

    func isDownloaded(volumeID: String) -> Bool {
        downloadedByID[volumeID] != nil
    }

    func offlinePages(for volumeID: String) -> [URL]? {
        downloadedByID[volumeID]?.pageURLs
    }

    func downloadedVolumes(forSeriesID seriesID: String) -> [OfflineVolume] {
        downloadedByID.values
            .filter { $0.seriesID == seriesID }
            .sorted { lhs, rhs in
                if lhs.volumeTitle == rhs.volumeTitle {
                    return lhs.downloadedAt > rhs.downloadedAt
                }
                return lhs.volumeTitle.localizedStandardCompare(rhs.volumeTitle) == .orderedAscending
            }
    }

    func downloadedSeries() -> [OfflineSeriesSummary] {
        let grouped = Dictionary(grouping: downloadedByID.values) { $0.seriesID }

        return grouped.map { seriesID, volumes in
            OfflineSeriesSummary(
                id: seriesID,
                title: volumes.first?.seriesTitle ?? "Offline Series",
                volumeCount: volumes.count
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func removeDownload(volumeID: String) throws {
        let finalDir = directoryURL(for: volumeID)
        if fileManager.fileExists(atPath: finalDir.path) {
            try fileManager.removeItem(at: finalDir)
        }
        reload()
    }

    func download(
        volume: Volume,
        series: Series,
        api: MangaAPI,
        progress: @escaping (_ completed: Int, _ total: Int) -> Void
    ) async throws {
        let pages = try await api.fetchPages(volumeID: volume.id)
        guard !pages.isEmpty else {
            throw OfflineLibraryError.noPages
        }

        let tempDir = rootURL
            .appendingPathComponent("\(safeDirectoryName(for: volume.id)).tmp-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            var pageFiles: [String] = []
            pageFiles.reserveCapacity(pages.count)

            for (index, page) in pages.enumerated() {
                guard let pageURL = absolutePageURL(rawPageURL: page.url, apiBaseURL: api.baseURL) else {
                    throw OfflineLibraryError.invalidPageURL
                }

                let (data, response) = try await URLSession.shared.data(from: pageURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw OfflineLibraryError.responseError
                }

                let ext = fileExtension(
                    mimeType: http.mimeType,
                    originalName: page.name,
                    fallbackURL: pageURL
                )
                let fileName = String(format: "%04d.%@", index + 1, ext)
                let fileURL = tempDir.appendingPathComponent(fileName)

                try data.write(to: fileURL, options: .atomic)
                pageFiles.append(fileName)
                progress(index + 1, pages.count)
            }

            let manifest = OfflineVolumeManifest(
                version: 1,
                volumeID: volume.id,
                volumeTitle: volume.title,
                volumeKind: volume.kind,
                seriesID: series.id,
                seriesTitle: series.title,
                downloadedAt: Date(),
                pageFiles: pageFiles
            )

            let manifestData = try Self.encoder.encode(manifest)
            try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"), options: .atomic)

            let finalDir = directoryURL(for: volume.id)
            if fileManager.fileExists(atPath: finalDir.path) {
                try fileManager.removeItem(at: finalDir)
            }
            try fileManager.moveItem(at: tempDir, to: finalDir)
            reload()
        } catch {
            try? fileManager.removeItem(at: tempDir)
            throw error
        }
    }

    private func reload() {
        var rebuilt: [String: OfflineVolume] = [:]
        let dirs = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for dir in dirs {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? Self.decoder.decode(OfflineVolumeManifest.self, from: data)
            else {
                continue
            }

            let pageURLs = manifest.pageFiles
                .map { dir.appendingPathComponent($0) }
                .filter { fileManager.fileExists(atPath: $0.path) }
                .sorted { lhs, rhs in
                    lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }

            guard !pageURLs.isEmpty else {
                continue
            }

            rebuilt[manifest.volumeID] = OfflineVolume(
                id: manifest.volumeID,
                volumeTitle: manifest.volumeTitle,
                volumeKind: manifest.volumeKind,
                seriesID: manifest.seriesID,
                seriesTitle: manifest.seriesTitle,
                downloadedAt: manifest.downloadedAt,
                pageURLs: pageURLs
            )
        }

        downloadedByID = rebuilt
    }

    private func createRootDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func absolutePageURL(rawPageURL: String, apiBaseURL: URL) -> URL? {
        if rawPageURL.hasPrefix("http://") || rawPageURL.hasPrefix("https://") {
            return URL(string: rawPageURL)
        }
        return URL(string: rawPageURL, relativeTo: apiBaseURL)?.absoluteURL
    }

    private static func makeRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("MangaReaderOffline", isDirectory: true)
    }

    private func directoryURL(for volumeID: String) -> URL {
        rootURL.appendingPathComponent(safeDirectoryName(for: volumeID), isDirectory: true)
    }

    private func safeDirectoryName(for volumeID: String) -> String {
        Data(volumeID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func fileExtension(mimeType: String?, originalName: String, fallbackURL: URL) -> String {
        if let mimeType, let type = UTType(mimeType: mimeType), let ext = type.preferredFilenameExtension {
            return ext.lowercased()
        }

        let nameExt = (originalName as NSString).pathExtension.lowercased()
        if !nameExt.isEmpty {
            return nameExt
        }

        let urlExt = fallbackURL.pathExtension.lowercased()
        if !urlExt.isEmpty {
            return urlExt
        }

        return "jpg"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
