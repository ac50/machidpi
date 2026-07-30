import Foundation

/// Display-mode facts extracted from CGDisplayMode, kept as plain values so
/// the selection logic is unit-testable without a display.
public struct ModeInfo: Equatable, Sendable {
    public let index: Int
    public let width: Int        // points
    public let height: Int
    public let pixelWidth: Int   // device pixels
    public let pixelHeight: Int
    public let refreshRate: Double

    public init(index: Int, width: Int, height: Int,
                pixelWidth: Int, pixelHeight: Int, refreshRate: Double)
    {
        self.index = index
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    /// HiDPI (Retina) modes back each point with more than one pixel.
    public var isHiDPI: Bool { pixelWidth > width }
}

public enum ModeSelection {
    /// The HiDPI mode whose point size equals the rung, preferring the
    /// highest refresh rate when several qualify.
    public static func hiDPIMode(matching rung: Rung, in modes: [ModeInfo]) -> ModeInfo? {
        modes
            .filter { $0.isHiDPI && $0.width == rung.width && $0.height == rung.height }
            .max { $0.refreshRate < $1.refreshRate }
    }

    /// The 1x mode that drives the panel at its native pixel grid, preferring
    /// the highest refresh rate. The mirror scaler must output native pixels;
    /// any other panel mode adds a second, blurry scaling pass in the monitor.
    public static func nativeMode(panelWidth: Int, panelHeight: Int,
                                  in modes: [ModeInfo]) -> ModeInfo?
    {
        modes
            .filter { !$0.isHiDPI && $0.pixelWidth == panelWidth && $0.pixelHeight == panelHeight }
            .max { $0.refreshRate < $1.refreshRate }
    }
}
