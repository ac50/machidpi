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
    // v0.1.2 kept one merged "arrangement" map mixing layouts recorded with
    // different display sets; it is deliberately ignored.
    private static let arrangementsKey = "arrangements"
    private static let builtinKey = "builtinLooksLike"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The layout saved for one set of arranged displays (see
    /// `Arrangement.topologyKey`), keyed by display UUID. The virtual
    /// display's UUID is stable across launches because its identity is fixed.
    public func arrangement(for topology: String) -> [String: DisplayOrigin]? {
        loadArrangements()[topology]
    }

    public func setArrangement(_ map: [String: DisplayOrigin], for topology: String) {
        var all = loadArrangements()
        all[topology] = map
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.arrangementsKey)
        }
    }

    /// Last seen "looks like" size of the built-in display, so the matching
    /// rung stays available while the lid is closed.
    public var builtinLooksLike: Rung? {
        get {
            guard let data = defaults.data(forKey: Self.builtinKey) else { return nil }
            return try? JSONDecoder().decode(Rung.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.builtinKey)
            } else {
                defaults.removeObject(forKey: Self.builtinKey)
            }
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

    private func loadArrangements() -> [String: [String: DisplayOrigin]] {
        guard let data = defaults.data(forKey: Self.arrangementsKey),
              let all = try? JSONDecoder().decode([String: [String: DisplayOrigin]].self, from: data)
        else { return [:] }
        return all
    }

    private func loadAll() -> [String: DisplayPrefs] {
        guard let data = defaults.data(forKey: Self.key),
              let all = try? JSONDecoder().decode([String: DisplayPrefs].self, from: data)
        else { return [:] }
        return all
    }
}
