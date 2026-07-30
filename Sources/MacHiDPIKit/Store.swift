import Foundation

/// Per-display persisted preferences, keyed by the display's stable UUID.
public struct DisplayPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var rung: Rung?
    /// Last known arrangement origin of the (virtual) display. Restored on
    /// enable: macOS only remembers the physical display's stale position,
    /// so relying on it resets the user's arrangement every login.
    public var originX: Int?
    public var originY: Int?

    public init(enabled: Bool, rung: Rung?, originX: Int? = nil, originY: Int? = nil) {
        self.enabled = enabled
        self.rung = rung
        self.originX = originX
        self.originY = originY
    }
}

/// A display's arrangement origin in global display coordinates.
public struct DisplayOrigin: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public final class Store {
    private static let key = "displays"
    private static let arrangementKey = "arrangement"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Snapshot of every display's origin while HiDPI was active, keyed by
    /// display UUID (the virtual display's UUID is stable across launches
    /// because its identity is fixed).
    public func arrangement() -> [String: DisplayOrigin] {
        guard let data = defaults.data(forKey: Self.arrangementKey),
              let map = try? JSONDecoder().decode([String: DisplayOrigin].self, from: data)
        else { return [:] }
        return map
    }

    public func setArrangement(_ map: [String: DisplayOrigin]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Self.arrangementKey)
        }
    }

    public func prefs(for uuid: String) -> DisplayPrefs? {
        loadAll()[uuid]
    }

    public func set(_ prefs: DisplayPrefs, for uuid: String) {
        var all = loadAll()
        all[uuid] = prefs
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func loadAll() -> [String: DisplayPrefs] {
        guard let data = defaults.data(forKey: Self.key),
              let all = try? JSONDecoder().decode([String: DisplayPrefs].self, from: data)
        else { return [:] }
        return all
    }
}
