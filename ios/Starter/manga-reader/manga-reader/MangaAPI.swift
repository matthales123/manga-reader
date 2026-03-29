import Foundation
import Combine

@MainActor
final class MangaAPI: ObservableObject {
    @Published private(set) var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func updateBaseURL(_ newURL: URL) {
        baseURL = newURL
    }

    func fetchSeries() async throws -> [Series] {
        let endpoint = makeEndpoint("api/library/series")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(SeriesListResponse.self, from: data).items
    }

    func fetchVolumes(seriesID: String) async throws -> [Volume] {
        let endpoint = makeEndpoint("api/library/series/\(seriesID)/volumes")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(VolumeListResponse.self, from: data).items
    }

    func fetchPages(volumeID: String) async throws -> [PageItem] {
        let endpoint = makeEndpoint("api/library/volumes/\(volumeID)/pages")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(PageListResponse.self, from: data).items
    }

    func fetchStoryArcs(seriesID: String) async throws -> [StoryArc] {
        let endpoint = makeEndpoint("api/library/series/\(seriesID)/arcs")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(ArcListResponse.self, from: data).items
    }

    func pageImageURL(volumeID: String, index: Int, cacheBuster: Int? = nil) -> URL {
        let endpoint = makeEndpoint("api/library/volumes/\(volumeID)/pages/\(index)")
        guard let cacheBuster else {
            return endpoint
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "r", value: String(cacheBuster))]
        return components?.url ?? endpoint
    }

    func seriesCoverURL(series: Series) -> URL? {
        guard let raw = series.coverURL else {
            return nil
        }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    func userFacingErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .appTransportSecurityRequiresSecureConnection:
                return "Blocked by App Transport Security. Add an ATS exception for \(baseURL.host ?? baseURL.absoluteString) in Info settings for development."
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                return "Cannot reach \(baseURL.absoluteString). Confirm backend is running, IP/port are correct, and iPhone is on the same LAN."
            case .notConnectedToInternet:
                return "No internet/network connection. Connect to the same LAN as the backend or use downloaded offline volumes."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func makeEndpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
