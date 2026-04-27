import Foundation

/// Level grid: 20 columns × 10 rows. Row 0 is the bottom; column 0 is the left.
/// Flat index: `row * LevelModel.columns + col`.
final class LevelModel {
    static let columns = 20
    static let rows = 10
    static var tileCount: Int { columns * rows }

    /// 0 = empty, 1 = block, 2 = spike
    private(set) var tiles: [Int]

    /// Set true when the player reaches the goal in playtest (local only; no publishing).
    private(set) var verified: Bool

    /// Tap timestamps recorded during playtest (milliseconds since playtest start).
    /// Reserved for a future replay/validation system; no playback UI in v1.
    private(set) var replayTapTimestampsMs: [Int64]

    init(tiles: [Int]? = nil, verified: Bool = false, replayTapTimestampsMs: [Int64] = []) {
        if let tiles, tiles.count == Self.tileCount {
            self.tiles = tiles
        } else {
            self.tiles = Array(repeating: 0, count: Self.tileCount)
        }
        self.verified = verified
        self.replayTapTimestampsMs = replayTapTimestampsMs
    }

    static func index(col: Int, row: Int) -> Int {
        row * columns + col
    }

    func tileAt(col: Int, row: Int) -> Int {
        guard col >= 0, col < Self.columns, row >= 0, row < Self.rows else { return 0 }
        return tiles[Self.index(col: col, row: row)]
    }

    func setTile(col: Int, row: Int, value: Int) {
        guard col >= 0, col < Self.columns, row >= 0, row < Self.rows else { return }
        let v = max(0, min(2, value))
        tiles[Self.index(col: col, row: row)] = v
    }

    func clearGrid() {
        tiles = Array(repeating: 0, count: Self.tileCount)
        verified = false
        replayTapTimestampsMs = []
    }

    func markVerified() {
        verified = true
    }

    func beginPlaytestRecording() {
        replayTapTimestampsMs = []
    }

    func recordJumpTap(elapsedMs: Int64) {
        replayTapTimestampsMs.append(elapsedMs)
    }

    // MARK: - Persistence (local only)

    private struct PersistedLevel: Codable {
        var tiles: [Int]
        var verified: Bool
        var replayTapTimestampsMs: [Int64]
    }

    private static let storageKey = "com.cuberun.buildmode.savedLevel"

    func saveToDisk() {
        let payload = PersistedLevel(tiles: tiles, verified: verified, replayTapTimestampsMs: replayTapTimestampsMs)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func loadFromDisk() -> LevelModel? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(PersistedLevel.self, from: data),
              payload.tiles.count == tileCount
        else { return nil }
        return LevelModel(tiles: payload.tiles, verified: payload.verified, replayTapTimestampsMs: payload.replayTapTimestampsMs)
    }
}
