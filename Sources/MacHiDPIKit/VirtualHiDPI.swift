import CGVirtualDisplayShim
import CoreGraphics
import Foundation

/// Creates a HiDPI-capable virtual display per physical display and hardware-
/// mirrors the physical panel onto it. Main-thread only.
public final class VirtualHiDPI {
    public enum Error: Swift.Error, LocalizedError {
        case creationFailed
        case applySettingsFailed
        case mirrorFailed(CGError)
        case modeNotFound

        public var errorDescription: String? {
            switch self {
            case .creationFailed: return "virtual display creation failed"
            case .applySettingsFailed: return "virtual display rejected mode settings"
            case .mirrorFailed(let e): return "mirror configuration failed (CGError \(e.rawValue))"
            case .modeNotFound: return "no matching HiDPI mode on virtual display"
            }
        }
    }

    public struct Session {
        public let physical: PhysicalDisplay
        public let virtualID: CGDirectDisplayID
        public let ladder: [Rung]
        public var currentRung: Rung
        let display: CGVirtualDisplay  // strong ref keeps the display alive
    }

    public private(set) var sessions: [CGDirectDisplayID: Session] = [:]

    /// Physical displays with an enable in flight. Guards against the
    /// startup race where our own mirror transaction fires a display-
    /// reconfiguration event that triggers a second enable — creating a
    /// duplicate virtual display with the same identity, which fails.
    public private(set) var pending: Set<CGDirectDisplayID> = []

    public var virtualIDs: Set<CGDirectDisplayID> {
        Set(sessions.values.map(\.virtualID))
    }

    public init() {}

    /// Create the virtual display, wait for WindowServer to register it,
    /// mirror the physical display onto it, then select the wanted rung.
    /// No-op while a session exists or an enable is already in flight.
    public func enable(_ physical: PhysicalDisplay, rung: Rung?,
                       completion: @escaping (Result<Void, Error>) -> Void)
    {
        guard sessions[physical.id] == nil, !pending.contains(physical.id) else { return }

        let ladder = Scaling.ladder(panelWidth: physical.pixelWidth,
                                    panelHeight: physical.pixelHeight)
        guard let target = rung.flatMap({ ladder.contains($0) ? $0 : nil })
            ?? Scaling.defaultRung(for: ladder, panelWidth: physical.pixelWidth),
            let maxRung = ladder.first
        else {
            completion(.failure(.modeNotFound))
            return
        }

        pending.insert(physical.id)
        let finish: (Result<Void, Error>) -> Void = { [self] result in
            pending.remove(physical.id)
            completion(result)
        }

        // Captured before mirroring: the virtual display takes the physical
        // display's place in the arrangement, and the panel must run its
        // native mode so the mirror scaler outputs 1:1 pixels.
        let arrangementOrigin = CGDisplayBounds(physical.id).origin
        let (physInfos, physRefs) = Displays.modeInfosWithRefs(for: physical.id)
        let nativeRef = ModeSelection.nativeMode(panelWidth: physical.pixelWidth,
                                                 panelHeight: physical.pixelHeight,
                                                 in: physInfos).map { physRefs[$0.index] }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "\(physical.name) (HiDPI)"
        descriptor.vendorID = physical.vendorID
        descriptor.productID = physical.productID
        descriptor.serialNumber = 0x4D48_4450  // "MHDP": stable identity
        descriptor.sizeInMillimeters = physical.sizeInMillimeters.width > 0
            ? physical.sizeInMillimeters : CGSize(width: 598, height: 336)
        descriptor.maxPixelsWide = UInt32(2 * maxRung.width)
        descriptor.maxPixelsHigh = UInt32(2 * maxRung.height)
        descriptor.queue = DispatchQueue(label: "machidpi.virtual-display")

        let icc = CGDisplayCopyColorSpace(physical.id).copyICCData() as Data?
        if let p = icc.flatMap(ICC.primaries(fromICC:)) {
            descriptor.redPrimary = p.red
            descriptor.greenPrimary = p.green
            descriptor.bluePrimary = p.blue
            descriptor.whitePoint = p.white
        } else {  // Display P3
            descriptor.redPrimary = CGPoint(x: 0.680, y: 0.320)
            descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.690)
            descriptor.bluePrimary = CGPoint(x: 0.150, y: 0.060)
            descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = ladder.map {
            CGVirtualDisplayMode(width: UInt32($0.width), height: UInt32($0.height),
                                 refreshRate: physical.refreshRate)
        }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            finish(.failure(.creationFailed))
            return
        }
        guard display.apply(settings) else {
            finish(.failure(.applySettingsFailed))
            return
        }
        let virtualID = CGDirectDisplayID(display.displayID)

        // Give WindowServer a beat to register the new display before the
        // mirror transaction references it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            switch Self.mirror(physical: physical.id, onto: virtualID,
                               virtualOrigin: arrangementOrigin,
                               physicalNativeMode: nativeRef)
            {
            case .success:
                sessions[physical.id] = Session(physical: physical, virtualID: virtualID,
                                                ladder: ladder, currentRung: target,
                                                display: display)
                // A freshly created virtual display may briefly report an
                // empty mode list; retry once after it settles.
                if !setRung(target, physicalID: physical.id) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        _ = self?.setRung(target, physicalID: physical.id)
                    }
                }
                finish(.success(()))
            case .failure(let error):
                finish(.failure(error))  // `display` goes out of scope → removed
            }
        }
    }

    /// Un-mirror first; drop the CGVirtualDisplay reference last so the
    /// mirror transaction commits before the display disappears.
    public func disable(physicalID: CGDirectDisplayID) {
        guard sessions[physicalID] != nil else { return }
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success {
            CGConfigureDisplayMirrorOfDisplay(config, physicalID, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        sessions[physicalID] = nil
    }

    /// Switch the virtual display to the HiDPI mode matching `rung` using
    /// only public APIs (enumerate duplicates, apply within a transaction).
    public func setRung(_ rung: Rung, physicalID: CGDirectDisplayID) -> Bool {
        guard var session = sessions[physicalID] else { return false }
        let (infos, refs) = Displays.modeInfosWithRefs(for: session.virtualID)
        guard let match = ModeSelection.hiDPIMode(matching: rung, in: infos) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, session.virtualID, refs[match.index], nil)
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else { return false }
        session.currentRung = rung
        sessions[physicalID] = session
        return true
    }

    public func disableAll() {
        for physicalID in Array(sessions.keys) { disable(physicalID: physicalID) }
    }

    private static func mirror(physical: CGDirectDisplayID,
                               onto virtualID: CGDirectDisplayID,
                               virtualOrigin: CGPoint,
                               physicalNativeMode: CGDisplayMode?) -> Result<Void, Error>
    {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            return .failure(.mirrorFailed(.failure))
        }
        if let mode = physicalNativeMode {
            CGConfigureDisplayWithDisplayMode(config, physical, mode, nil)
        }
        CGConfigureDisplayMirrorOfDisplay(config, physical, virtualID)
        CGConfigureDisplayOrigin(config, virtualID,
                                 Int32(virtualOrigin.x), Int32(virtualOrigin.y))
        let error = CGCompleteDisplayConfiguration(config, .forSession)
        return error == .success ? .success(()) : .failure(.mirrorFailed(error))
    }
}
