import XCTest
@testable import MacHiDPIKit

final class ModeSelectionTests: XCTestCase {
    private func mode(_ i: Int, _ w: Int, _ h: Int, px: Int, ph: Int, hz: Double = 60)
        -> ModeInfo
    {
        ModeInfo(index: i, width: w, height: h, pixelWidth: px, pixelHeight: ph, refreshRate: hz)
    }

    func testIsHiDPI() {
        XCTAssertTrue(mode(0, 1920, 1080, px: 3840, ph: 2160).isHiDPI)
        XCTAssertFalse(mode(0, 1920, 1080, px: 1920, ph: 1080).isHiDPI)
    }

    func testMatchesExactHiDPIVariant() {
        let modes = [
            mode(0, 1920, 1080, px: 1920, ph: 1080),          // 1x — must be ignored
            mode(1, 1920, 1080, px: 3840, ph: 2160),          // 2x — the one we want
            mode(2, 2560, 1440, px: 5120, ph: 2880),
        ]
        let match = ModeSelection.hiDPIMode(matching: Rung(width: 1920, height: 1080), in: modes)
        XCTAssertEqual(match?.index, 1)
    }

    func testPrefersHigherRefreshRate() {
        let modes = [
            mode(0, 1920, 1080, px: 3840, ph: 2160, hz: 60),
            mode(1, 1920, 1080, px: 3840, ph: 2160, hz: 120),
        ]
        let match = ModeSelection.hiDPIMode(matching: Rung(width: 1920, height: 1080), in: modes)
        XCTAssertEqual(match?.index, 1)
    }

    func testNoMatchReturnsNil() {
        let modes = [mode(0, 1920, 1080, px: 1920, ph: 1080)]  // only 1x
        XCTAssertNil(ModeSelection.hiDPIMode(matching: Rung(width: 1920, height: 1080), in: modes))
        XCTAssertNil(ModeSelection.hiDPIMode(matching: Rung(width: 1280, height: 720), in: []))
    }
}
