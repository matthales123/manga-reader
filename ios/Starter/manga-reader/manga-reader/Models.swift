import Foundation
import Combine

struct SeriesListResponse: Codable {
    let items: [Series]
}

struct Series: Codable, Identifiable, Hashable {
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

struct VolumeListResponse: Codable {
    let items: [Volume]
}

struct ArcListResponse: Codable {
    let items: [StoryArc]
}

struct StoryArc: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let startChapter: Double?
    let endChapter: Double?
    let order: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case startChapter = "start_chapter"
        case endChapter = "end_chapter"
        case order
    }
}

struct Volume: Codable, Identifiable, Hashable {
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

struct PageListResponse: Codable {
    let items: [PageItem]
}

struct PageItem: Codable, Identifiable {
    let index: Int
    let name: String
    let url: String

    var id: Int { index }
}
