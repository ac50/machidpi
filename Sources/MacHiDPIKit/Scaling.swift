import Foundation

/// A "looks like" logical resolution offered to the user.
public struct Rung: Equatable, Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    public var label: String { "\(width) × \(height)" }
}

public enum Scaling {
    /// Fractions of the panel size offered as "looks like" rungs, descending.
    static let factors: [Double] = [1.0, 0.8, 0.75, 2.0 / 3.0, 0.625, 0.5]
    static let minHeight = 720

    /// Ladder of HiDPI "looks like" resolutions for a physical panel:
    /// even-sized, deduplicated, descending, heights below 720 dropped.
    public static func ladder(panelWidth: Int, panelHeight: Int) -> [Rung] {
        guard panelWidth > 0, panelHeight > 0 else { return [] }
        var seen = Set<Rung>()
        var rungs: [Rung] = []
        for factor in factors {
            let rung = Rung(
                width: 2 * Int(Double(panelWidth) * factor / 2),
                height: 2 * Int(Double(panelHeight) * factor / 2)
            )
            guard rung.height >= minHeight, seen.insert(rung).inserted else { continue }
            rungs.append(rung)
        }
        return rungs
    }

    /// Default selection: the rung closest to 2/3 of the panel width —
    /// matches macOS's own default ("looks like 2560×1440" on a 27" 4K).
    public static func defaultRung(for ladder: [Rung], panelWidth: Int) -> Rung? {
        let target = Double(panelWidth) * 2.0 / 3.0
        return ladder.min { abs(Double($0.width) - target) < abs(Double($1.width) - target) }
    }
}
