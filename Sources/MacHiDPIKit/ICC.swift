import CoreGraphics
import Foundation

public enum ICC {
    public struct Primaries: Equatable {
        public let red: CGPoint
        public let green: CGPoint
        public let blue: CGPoint
        public let white: CGPoint
    }

    /// CIE xy chromaticities parsed from an ICC profile's rXYZ/gXYZ/bXYZ/wtpt
    /// tags. Returns nil when the profile is missing or malformed.
    public static func primaries(fromICC data: Data) -> Primaries? {
        guard data.count > 132 else { return nil }
        let tagCount = uint32(data, at: 128)

        var tagOffsets: [UInt32: Int] = [:]
        for i in 0 ..< Int(tagCount) {
            let base = 132 + i * 12
            guard base + 12 <= data.count else { break }
            tagOffsets[uint32(data, at: base)] = Int(uint32(data, at: base + 4))
        }

        func chromaticity(_ signature: UInt32) -> CGPoint? {
            guard let offset = tagOffsets[signature], offset + 20 <= data.count else { return nil }
            let base = offset + 8  // skip 'XYZ ' type signature + reserved
            let x = s15Fixed16(data, at: base)
            let y = s15Fixed16(data, at: base + 4)
            let z = s15Fixed16(data, at: base + 8)
            let sum = x + y + z
            guard sum > 0 else { return nil }
            return CGPoint(x: x / sum, y: y / sum)
        }

        guard let r = chromaticity(0x7258_595A),  // rXYZ
              let g = chromaticity(0x6758_595A),  // gXYZ
              let b = chromaticity(0x6258_595A),  // bXYZ
              let w = chromaticity(0x7774_7074)   // wtpt
        else { return nil }
        return Primaries(red: r, green: g, blue: b, white: w)
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16
            | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }

    private static func s15Fixed16(_ data: Data, at offset: Int) -> Double {
        Double(Int32(bitPattern: uint32(data, at: offset))) / 65536.0
    }
}
