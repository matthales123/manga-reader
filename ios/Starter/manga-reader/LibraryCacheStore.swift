import Foundation

enum LibraryCacheStore {
    private static let seriesKey = "manga_reader_cached_series"
    private static let volumePrefix = "manga_reader_cached_volumes_"
    private static let arcPrefix = "manga_reader_cached_arcs_"

    static func loadSeries() -> [Series] {
        guard let data = UserDefaults.standard.data(forKey: seriesKey) else {
            return []
        }
        return (try? JSONDecoder().decode([Series].self, from: data)) ?? []
    }

    static func saveSeries(_ series: [Series]) {
        guard let data = try? JSONEncoder().encode(series) else {
            return
        }
        UserDefaults.standard.set(data, forKey: seriesKey)
    }

    static func loadVolumes(seriesID: String) -> [Volume] {
        let key = volumePrefix + seriesID
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([Volume].self, from: data)) ?? []
    }

    static func saveVolumes(seriesID: String, volumes: [Volume]) {
        let key = volumePrefix + seriesID
        guard let data = try? JSONEncoder().encode(volumes) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func loadArcs(seriesID: String) -> [StoryArc] {
        let key = arcPrefix + seriesID
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([StoryArc].self, from: data)) ?? []
    }

    static func saveArcs(seriesID: String, arcs: [StoryArc]) {
        let key = arcPrefix + seriesID
        guard let data = try? JSONEncoder().encode(arcs) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
