import XCTest
@testable import MacHiDPIKit

final class ScalingTests: XCTestCase {
    func testLadder2560x1440() {
        XCTAssertEqual(Scaling.ladder(panelWidth: 2560, panelHeight: 1440), [
            Rung(width: 2560, height: 1440),
            Rung(width: 2048, height: 1152),
            Rung(width: 1920, height: 1080),
            Rung(width: 1706, height: 960),
            Rung(width: 1600, height: 900),
            Rung(width: 1280, height: 720),
        ])
    }

    func testLadder3840x2160() {
        XCTAssertEqual(Scaling.ladder(panelWidth: 3840, panelHeight: 2160), [
            Rung(width: 3840, height: 2160),
            Rung(width: 3072, height: 1728),
            Rung(width: 2880, height: 1620),
            Rung(width: 2560, height: 1440),
            Rung(width: 2400, height: 1350),
            Rung(width: 1920, height: 1080),
        ])
    }

    func testLadder1920x1080FiltersBelow720() {
        XCTAssertEqual(Scaling.ladder(panelWidth: 1920, panelHeight: 1080), [
            Rung(width: 1920, height: 1080),
            Rung(width: 1536, height: 864),
            Rung(width: 1440, height: 810),
            Rung(width: 1280, height: 720),
        ])
    }

    func testLadderInvalidInputIsEmpty() {
        XCTAssertTrue(Scaling.ladder(panelWidth: 0, panelHeight: 1440).isEmpty)
        XCTAssertTrue(Scaling.ladder(panelWidth: -1, panelHeight: -1).isEmpty)
        XCTAssertTrue(Scaling.ladder(panelWidth: 640, panelHeight: 480).isEmpty)
    }

    func testDefaultRungPrefersTwoThirds() {
        let ladder = Scaling.ladder(panelWidth: 2560, panelHeight: 1440)
        XCTAssertEqual(Scaling.defaultRung(for: ladder, panelWidth: 2560),
                       Rung(width: 1706, height: 960))
        let ladder4k = Scaling.ladder(panelWidth: 3840, panelHeight: 2160)
        XCTAssertEqual(Scaling.defaultRung(for: ladder4k, panelWidth: 3840),
                       Rung(width: 2560, height: 1440))
        XCTAssertNil(Scaling.defaultRung(for: [], panelWidth: 2560))
    }
}
