import Foundation

/// Pure arrangement decisions, kept free of CoreGraphics so they are
/// unit-testable without displays. Layouts are saved per set of arranged
/// displays: an origin only makes sense next to the displays it was
/// recorded with.
public enum Arrangement {
    /// Identifies a set of arranged displays, independent of order.
    public static func topologyKey(_ uuids: Set<String>) -> String {
        uuids.sorted().joined(separator: ",")
    }

    /// Origins to apply so the arranged displays match the layout saved for
    /// exactly this set of displays. A lone display always sits at (0,0) and
    /// a layout with no display at (0,0) cannot exist, so neither is ever
    /// requested — Quartz would only re-tile, moving the main display.
    public static func restoreMoves(current: [String: DisplayOrigin],
                                    saved: [String: DisplayOrigin]) -> [String: DisplayOrigin]
    {
        guard current.count >= 2, Set(saved.keys) == Set(current.keys),
              saved.values.contains(DisplayOrigin(x: 0, y: 0))
        else { return [:] }
        var moves: [String: DisplayOrigin] = [:]
        for (uuid, origin) in current {
            if let target = saved[uuid], target != origin {
                moves[uuid] = target
            }
        }
        return moves
    }

    /// The layout worth remembering for the current displays, or nil when it
    /// is not a real arrangement (a lone display, e.g. with the lid closed).
    /// Physical panels in `excluding` belong inside a mirror set.
    public static func snapshot(of current: [String: DisplayOrigin],
                                excluding: Set<String>) -> [String: DisplayOrigin]?
    {
        let map = current.filter { !excluding.contains($0.key) }
        return map.count >= 2 ? map : nil
    }
}

/// Bounds automatic re-enables of a display whose enable keeps failing.
/// Each failure releases the virtual display, which itself fires a display
/// reconfiguration event; without a bound that is an endless create/destroy
/// loop (screens flashing every few seconds).
public struct RetryBudget {
    public let limit: Int
    private var failures: [String: Int] = [:]

    public init(limit: Int) {
        self.limit = limit
    }

    public func allows(_ key: String) -> Bool {
        failures[key, default: 0] < limit
    }

    public mutating func recordFailure(_ key: String) {
        failures[key, default: 0] += 1
    }

    public mutating func reset(_ key: String) {
        failures[key] = nil
    }

    /// Forget displays that went away: a replug deserves fresh attempts.
    public mutating func keep(only present: Set<String>) {
        failures = failures.filter { present.contains($0.key) }
    }
}
