import Foundation

@MainActor
final class MangaAPI: ObservableObject {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func fetchSeries() async throws -> [Series] {
        let endpoint = baseURL.appending(path: "/api/library/series")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(SeriesListResponse.self, from: data).items
    }

    func fetchVolumes(seriesID: String) async throws -> [Volume] {
        let endpoint = baseURL.appending(path: "/api/library/series/\(seriesID)/volumes")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(VolumeListResponse.self, from: data).items
    }

    func fetchPages(volumeID: String) async throws -> [PageItem] {
        let endpoint = baseURL.appending(path: "/api/library/volumes/\(volumeID)/pages")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try validateResponse(response)
        return try JSONDecoder().decode(PageListResponse.self, from: data).items
    }

    func pageImageURL(volumeID: String, index: Int, cacheBuster: Int? = nil) -> URL {
        let endpoint = baseURL.appending(path: "/api/library/volumes/\(volumeID)/pages/\(index)")
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

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
