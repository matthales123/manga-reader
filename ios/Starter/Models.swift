import Foundation

struct SeriesListResponse: Decodable {
    let items: [Series]
}

struct Series: Decodable, Identifiable {
    let id: String
    let title: String
    let relativePath: String
    let volumeCount: Int
    let coverURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case relativePath = "relative_path"
        case volumeCount = "volume_count"
        case coverURL = "cover_url"
    }
}

struct VolumeListResponse: Decodable {
    let items: [Volume]
}

struct Volume: Decodable, Identifiable {
    let id: String
    let title: String
    let relativePath: String
    let kind: String
    let seriesId: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case relativePath = "relative_path"
        case kind
        case seriesId = "series_id"
    }
}

struct PageListResponse: Decodable {
    let items: [PageItem]
}

struct PageItem: Decodable, Identifiable {
    let index: Int
    let name: String
    let url: String

    var id: Int { index }
}
