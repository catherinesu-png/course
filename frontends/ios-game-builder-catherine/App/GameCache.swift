import Foundation

/// The last downloaded games list, kept only so pass-and-play works offline.
enum GameCache {
    struct Snapshot: Codable {
        let games: [Game]
        let savedAt: Date
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("games-cache.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ games: [Game]) {
        guard let data = try? JSONEncoder().encode(Snapshot(games: games, savedAt: .now)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
