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

public final class Store {
    private static let key = "displays"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
