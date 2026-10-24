import XCTest
@testable import MacHiDPIKit

final class ArrangementTests: XCTestCase {
    private let builtin = "uuid-builtin"
    private let virtual = "uuid-virtual"
    private let panel = "uuid-panel"

    func testTopologyKeyIgnoresOrder() {
        XCTAssertEqual(Arrangement.topologyKey([virtual, builtin]),
                       Arrangement.topologyKey([builtin, virtual]))
        XCTAssertNotEqual(Arrangement.topologyKey([builtin, virtual]),
                          Arrangement.topologyKey([builtin, panel]))
    }

    func testRestoreMovesOnlyDisplaysAwayFromSavedOrigin() {
        let saved = [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: 1470, y: 0)]
        let current = [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: -2560, y: 0)]
        XCTAssertEqual(Arrangement.restoreMoves(current: current, saved: saved),
                       [virtual: DisplayOrigin(x: 1470, y: 0)])
        XCTAssertEqual(Arrangement.restoreMoves(current: saved, saved: saved), [:])
    }

    func testRestoreNeverMovesALoneDisplay() {
        // Lid closed: the virtual display is alone and always at (0,0).
        XCTAssertEqual(Arrangement.restoreMoves(current: [virtual: DisplayOrigin(x: 0, y: 0)],
                                                saved: [virtual: DisplayOrigin(x: 1470, y: 0)]),
                       [:])
    }

    func testRestoreNeedsExactlyTheSavedDisplays() {
        let saved = [builtin: DisplayOrigin(x: 0, y: 0), "uuid-other": DisplayOrigin(x: 1920, y: 0)]
        let current = [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: 1470, y: 0)]
        XCTAssertEqual(Arrangement.restoreMoves(current: current, saved: saved), [:])
    }

    func testRestoreRejectsLayoutWithoutMainDisplay() {
        // No display at (0,0): Quartz would re-tile and move the menu bar.
        let saved = [builtin: DisplayOrigin(x: -1470, y: 200), virtual: DisplayOrigin(x: 1470, y: 0)]
        let current = [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: 1470, y: 0)]
        XCTAssertEqual(Arrangement.restoreMoves(current: current, saved: saved), [:])
    }

    func testSnapshotSkipsLoneDisplaysAndPanels() {
        XCTAssertNil(Arrangement.snapshot(of: [virtual: DisplayOrigin(x: 0, y: 0)], excluding: []))
        // A panel seen while its mirror was briefly broken is never recorded.
        let current = [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: 1470, y: 0),
                       panel: DisplayOrigin(x: 4030, y: 0)]
        XCTAssertEqual(Arrangement.snapshot(of: current, excluding: [panel]),
                       [builtin: DisplayOrigin(x: 0, y: 0), virtual: DisplayOrigin(x: 1470, y: 0)])
        XCTAssertNil(Arrangement.snapshot(of: [virtual: DisplayOrigin(x: 0, y: 0),
                                               panel: DisplayOrigin(x: 1470, y: 0)],
                                          excluding: [panel]))
    }

    func testRetryBudgetStopsAfterLimit() {
        var budget = RetryBudget(limit: 3)
        for _ in 0..<3 {
            XCTAssertTrue(budget.allows(panel))
            budget.recordFailure(panel)
        }
        XCTAssertFalse(budget.allows(panel))
        XCTAssertTrue(budget.allows(builtin))  // budgets are per display
        budget.reset(panel)
        XCTAssertTrue(budget.allows(panel))
    }

    func testRetryBudgetForgetsDisplaysThatLeft() {
        var budget = RetryBudget(limit: 1)
        budget.recordFailure(panel)
        budget.keep(only: [panel])
        XCTAssertFalse(budget.allows(panel))  // still connected: stays blocked
        budget.keep(only: [])
        XCTAssertTrue(budget.allows(panel))  // replugged: fresh attempts
    }
}
