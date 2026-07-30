import XCTest
@testable import MacHiDPIKit

final class ICCTests: XCTestCase {
    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private func s15Fixed16(_ v: Double) -> [UInt8] {
        be32(UInt32(bitPattern: Int32(v * 65536)))
    }

    /// Minimal ICC profile: 128-byte header + tag count + 4 tag entries +
    /// 4 XYZ data blocks ('XYZ ' sig + 4 reserved + 3 × s15Fixed16).
    private func syntheticProfile() -> Data {
        let tags: [(UInt32, (Double, Double, Double))] = [
            (0x7258_595A, (0.436, 0.222, 0.014)),  // rXYZ
            (0x6758_595A, (0.385, 0.717, 0.097)),  // gXYZ
            (0x6258_595A, (0.143, 0.061, 0.714)),  // bXYZ
            (0x7774_7074, (0.9642, 1.0, 0.8249)),  // wtpt
        ]
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes += be32(UInt32(tags.count))
        let dataStart = 132 + tags.count * 12
        for (i, tag) in tags.enumerated() {
            bytes += be32(tag.0)
            bytes += be32(UInt32(dataStart + i * 20))
            bytes += be32(20)
        }
        for (_, xyz) in tags {
            bytes += be32(0x58595A20)  // 'XYZ '
            bytes += be32(0)
            bytes += s15Fixed16(xyz.0) + s15Fixed16(xyz.1) + s15Fixed16(xyz.2)
        }
        return Data(bytes)
    }

    func testParsesSyntheticProfile() throws {
        let p = try XCTUnwrap(ICC.primaries(fromICC: syntheticProfile()))
        // chromaticity x = X/(X+Y+Z), y = Y/(X+Y+Z)
        XCTAssertEqual(p.red.x, 0.436 / 0.672, accuracy: 0.001)
        XCTAssertEqual(p.red.y, 0.222 / 0.672, accuracy: 0.001)
        XCTAssertEqual(p.white.x, 0.9642 / 2.7891, accuracy: 0.001)
        XCTAssertEqual(p.white.y, 1.0 / 2.7891, accuracy: 0.001)
    }

    func testRejectsTruncatedOrEmptyData() {
        XCTAssertNil(ICC.primaries(fromICC: Data()))
        XCTAssertNil(ICC.primaries(fromICC: syntheticProfile().prefix(140)))
    }
}
