import XCTest
@testable import MacHiDPIKit

final class StoreTests: XCTestCase {
    // Unique suite per test: `swift test --parallel` spreads methods across
    // processes, and a shared on-disk defaults domain would race.
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: Store!

    override func setUp() {
        super.setUp()
        suiteName = "machidpi.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = Store(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMissingUUIDReturnsNil() {
        XCTAssertNil(store.prefs(for: "no-such-display"))
    }

    func testRoundTrip() {
        let prefs = DisplayPrefs(enabled: true, rung: Rung(width: 1920, height: 1080))
        store.set(prefs, for: "uuid-a")
        XCTAssertEqual(store.prefs(for: "uuid-a"), prefs)
        // survives a fresh Store over the same defaults
        XCTAssertEqual(Store(defaults: defaults).prefs(for: "uuid-a"), prefs)
    }

    func testOriginRoundTrip() {
        let prefs = DisplayPrefs(enabled: true, rung: Rung(width: 1920, height: 1080),
                                 originX: -2560, originY: 180)
        store.set(prefs, for: "uuid-a")
        XCTAssertEqual(store.prefs(for: "uuid-a"), prefs)
    }

    func testDecodesLegacyPayloadWithoutOrigin() {
        // Payload written by v0.1 builds, before origin fields existed.
        let legacy = #"{"uuid-a":{"enabled":true,"rung":{"width":1920,"height":1080}}}"#
        defaults.set(Data(legacy.utf8), forKey: "displays")
        let prefs = store.prefs(for: "uuid-a")
        XCTAssertEqual(prefs?.enabled, true)
        XCTAssertEqual(prefs?.rung, Rung(width: 1920, height: 1080))
        XCTAssertNil(prefs?.originX)
    }

    func testUpdateOverwritesAndKeepsOthers() {
        store.set(DisplayPrefs(enabled: true, rung: nil), for: "uuid-a")
        store.set(DisplayPrefs(enabled: false, rung: nil), for: "uuid-b")
        store.set(DisplayPrefs(enabled: true, rung: Rung(width: 2560, height: 1440)), for: "uuid-a")
        XCTAssertEqual(store.prefs(for: "uuid-a"),
                       DisplayPrefs(enabled: true, rung: Rung(width: 2560, height: 1440)))
        XCTAssertEqual(store.prefs(for: "uuid-b"), DisplayPrefs(enabled: false, rung: nil))
    }
}
