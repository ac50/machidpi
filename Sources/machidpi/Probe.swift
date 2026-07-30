import CGVirtualDisplayShim
import CoreGraphics
import Foundation
import MacHiDPIKit

/// Diagnostic used by CI smoke tests and bug reports: enumerate displays,
/// then create and destroy a throwaway virtual display.
func runProbe() -> Int32 {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    print("probe: \(count) online display(s)")
    guard count > 0 else {
        print("probe: FAIL — no WindowServer session")
        return 2
    }

    for display in Displays.external(excluding: []) {
        print("probe: external \"\(display.name)\" id=\(display.id) "
            + "panel=\(display.pixelWidth)x\(display.pixelHeight) "
            + "@\(Int(display.refreshRate))Hz "
            + "vendor=0x\(String(display.vendorID, radix: 16)) "
            + "product=0x\(String(display.productID, radix: 16))")
        let ladder = Scaling.ladder(panelWidth: display.pixelWidth,
                                    panelHeight: display.pixelHeight)
        print("probe:   ladder: \(ladder.map(\.label).joined(separator: ", "))")
    }

    let descriptor = CGVirtualDisplayDescriptor()
    descriptor.name = "machidpi probe"
    descriptor.vendorID = 0x4D48
    descriptor.productID = 0x4450
    descriptor.serialNumber = 1
    descriptor.sizeInMillimeters = CGSize(width: 598, height: 336)
    descriptor.maxPixelsWide = 3840
    descriptor.maxPixelsHigh = 2160
    descriptor.redPrimary = CGPoint(x: 0.680, y: 0.320)
    descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.690)
    descriptor.bluePrimary = CGPoint(x: 0.150, y: 0.060)
    descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)
    descriptor.queue = DispatchQueue(label: "machidpi.probe")

    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 1
    settings.modes = [CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)]

    guard let display = CGVirtualDisplay(descriptor: descriptor) else {
        print("probe: FAIL — CGVirtualDisplay(descriptor:) returned nil")
        return 1
    }
    let applied = display.apply(settings)
    print("probe: virtual display id=\(display.displayID) applySettings=\(applied)")
    Thread.sleep(forTimeInterval: 1.0)

    let (infos, _) = Displays.modeInfosWithRefs(for: CGDirectDisplayID(display.displayID))
    let hiDPICount = infos.filter(\.isHiDPI).count
    print("probe: virtual display exposes \(infos.count) mode(s), \(hiDPICount) HiDPI")
    print(applied ? "probe: PASS" : "probe: PASS (applySettings=false)")
    return 0
}
