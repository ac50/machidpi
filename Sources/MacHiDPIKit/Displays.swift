import AppKit
import CoreGraphics

/// Facts about a physical (non-builtin) display.
public struct PhysicalDisplay {
    public let id: CGDirectDisplayID
    public let uuid: String
    public let name: String
    public let pixelWidth: Int   // native panel pixels
    public let pixelHeight: Int
    public let refreshRate: Double
    public let vendorID: UInt32
    public let productID: UInt32
    public let sizeInMillimeters: CGSize
}

public enum Displays {
    /// Online displays that are candidates for HiDPI: not built-in and not
    /// in `excluding` (our own virtual displays).
    public static func external(excluding: Set<CGDirectDisplayID>) -> [PhysicalDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0, !excluding.contains(id),
                  let uuid = uuidString(for: id) else { return nil }
            let panel = panelPixels(for: id)
            guard panel.width > 0 else { return nil }
            let refresh = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0
            return PhysicalDisplay(
                id: id,
                uuid: uuid,
                name: name(for: id),
                pixelWidth: panel.width,
                pixelHeight: panel.height,
                refreshRate: refresh > 0 ? refresh : 60,
                vendorID: CGDisplayVendorNumber(id),
                productID: CGDisplayModelNumber(id),
                sizeInMillimeters: CGDisplayScreenSize(id)
            )
        }
    }

    /// Stable identity that survives replugging (CGDirectDisplayID does not).
    public static func uuidString(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// All modes of a display including the HiDPI duplicates, as testable
    /// ModeInfo values plus the parallel CGDisplayMode refs needed to apply.
    public static func modeInfosWithRefs(for id: CGDirectDisplayID)
        -> (infos: [ModeInfo], refs: [CGDisplayMode])
    {
        // NSDictionary literal: CFString keys are not Hashable in Swift.
        let options: NSDictionary = [kCGDisplayShowDuplicateLowResolutionModes as NSString: true]
        guard let refs = CGDisplayCopyAllDisplayModes(id, options as CFDictionary) as? [CGDisplayMode]
        else { return ([], []) }
        let infos = refs.enumerated().map { index, mode in
            ModeInfo(index: index,
                     width: mode.width, height: mode.height,
                     pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                     refreshRate: mode.refreshRate)
        }
        return (infos, refs)
    }

    /// Native panel resolution: the largest pixel area over the full,
    /// duplicate-inclusive mode list (kDisplayModeNativeFlag is deprecated).
    static func panelPixels(for id: CGDirectDisplayID) -> (width: Int, height: Int) {
        let (infos, _) = modeInfosWithRefs(for: id)
        let best = infos.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        if let best { return (best.pixelWidth, best.pixelHeight) }
        return (CGDisplayPixelsWide(id), CGDisplayPixelsHigh(id))
    }

    static func name(for id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[key] as? NSNumber,
               CGDirectDisplayID(number.uint32Value) == id
            {
                return screen.localizedName
            }
        }
        return "Display \(id)"  // mirrored displays drop out of NSScreen.screens
    }
}
