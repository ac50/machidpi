import AppKit
import MacHiDPIKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = Store()
    private let hidpi = VirtualHiDPI()
    private var lastErrors: [String: String] = [:]  // uuid -> message
    private var reconcileWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.tv",
                                           accessibilityDescription: "machidpi")

        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo else { return }
            Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
                .scheduleReconcile()
        }, Unmanaged.passUnretained(self).toOpaque())

        reconcile()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hidpi.disableAll()
    }

    // MARK: - Reconciliation (hotplug self-healing)

    /// Display reconfiguration events arrive in bursts; debounce them.
    func scheduleReconcile() {
        reconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Make reality match preferences: tear down sessions whose physical
    /// display vanished; enable remembered displays that (re)appeared.
    private func reconcile() {
        persistOrigins()
        let externals = Displays.external(excluding: hidpi.virtualIDs)
        let presentIDs = Set(externals.map(\.id))

        for physicalID in hidpi.sessions.keys where !presentIDs.contains(physicalID) {
            hidpi.disable(physicalID: physicalID)
        }
        for display in externals
        where hidpi.sessions[display.id] == nil
            && !hidpi.pending.contains(display.id)
            && store.prefs(for: display.uuid)?.enabled == true
        {
            enableDisplay(display, rung: store.prefs(for: display.uuid)?.rung)
        }
        rebuildMenu()
    }

    /// Remember where the user placed every display while HiDPI is active
    /// (arrangement changes arrive as reconfiguration events). Skipped while
    /// an enable is in flight so transient layouts are never recorded.
    private func persistOrigins() {
        guard hidpi.pending.isEmpty, !hidpi.sessions.isEmpty else { return }

        for session in hidpi.sessions.values {
            let origin = CGDisplayBounds(session.virtualID).origin
            var prefs = store.prefs(for: session.physical.uuid)
                ?? DisplayPrefs(enabled: true, rung: session.currentRung)
            if prefs.originX != Int(origin.x) || prefs.originY != Int(origin.y) {
                prefs.originX = Int(origin.x)
                prefs.originY = Int(origin.y)
                store.set(prefs, for: session.physical.uuid)
            }
        }

        var map: [String: DisplayOrigin] = [:]
        for id in Displays.onlineIDs() where !Displays.isMirrorSlave(id) {
            guard let uuid = Displays.uuidString(for: id) else { continue }
            let origin = CGDisplayBounds(id).origin
            map[uuid] = DisplayOrigin(x: Int(origin.x), y: Int(origin.y))
        }
        if !map.isEmpty, map != store.arrangement() {
            store.setArrangement(map)
        }
    }

    /// Quartz auto-repositions every display we did not explicitly place
    /// when the mirror forms — and the virtual display's point size differs
    /// from the physical's, so neighbours get repacked. Re-apply the whole
    /// saved arrangement in one transaction.
    private func restoreArrangement(_ saved: [String: DisplayOrigin]) {
        guard !saved.isEmpty else { return }
        var moves: [(CGDirectDisplayID, DisplayOrigin)] = []
        for id in Displays.onlineIDs() where !Displays.isMirrorSlave(id) {
            guard let uuid = Displays.uuidString(for: id), let target = saved[uuid]
            else { continue }
            let current = CGDisplayBounds(id).origin
            if Int(current.x) != target.x || Int(current.y) != target.y {
                moves.append((id, target))
            }
        }
        guard !moves.isEmpty else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for (id, target) in moves {
            CGConfigureDisplayOrigin(config, id, Int32(target.x), Int32(target.y))
        }
        _ = CGCompleteDisplayConfiguration(config, .forSession)
    }

    private func enableDisplay(_ display: PhysicalDisplay, rung: Rung?) {
        lastErrors[display.uuid] = nil
        let saved = store.prefs(for: display.uuid)
        let origin = saved.flatMap { prefs in
            prefs.originX.flatMap { x in prefs.originY.map { y in
                CGPoint(x: Double(x), y: Double(y))
            } }
        }
        // Captured up front: reconciles during the enable could otherwise
        // overwrite the snapshot before it is restored.
        let savedArrangement = store.arrangement()

        hidpi.enable(display, rung: rung, origin: origin) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                var prefs = self.store.prefs(for: display.uuid)
                    ?? DisplayPrefs(enabled: true, rung: nil)
                prefs.enabled = true
                prefs.rung = self.hidpi.sessions[display.id]?.currentRung
                self.store.set(prefs, for: display.uuid)
                self.restoreArrangement(savedArrangement)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.restoreArrangement(savedArrangement)
                    self?.persistOrigins()
                }
            case .failure(let error):
                self.lastErrors[display.uuid] = error.localizedDescription
            }
            self.rebuildMenu()
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let externals = Displays.external(excluding: hidpi.virtualIDs)

        if externals.isEmpty && hidpi.sessions.isEmpty {
            menu.addItem(disabledItem("No external display"))
        }

        for display in externals {
            let session = hidpi.sessions[display.id]
            menu.addItem(disabledItem(session?.physical.name ?? display.name))

            let toggle = NSMenuItem(title: "Enable HiDPI",
                                    action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.state = session != nil ? .on : .off
            toggle.representedObject = DisplayRef(display: display)
            menu.addItem(toggle)

            if let error = lastErrors[display.uuid] {
                menu.addItem(disabledItem("⚠︎ \(error)"))
            }

            if let session {
                for rung in session.ladder {
                    let exact = Scaling.isPixelExact(rung,
                                                     panelWidth: display.pixelWidth,
                                                     panelHeight: display.pixelHeight)
                    let item = NSMenuItem(title: exact ? "\(rung.label)  ✦" : rung.label,
                                          action: #selector(selectRung(_:)), keyEquivalent: "")
                    item.target = self
                    item.state = rung == session.currentRung ? .on : .off
                    item.indentationLevel = 1
                    item.representedObject = DisplayRef(display: display, rung: rung)
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
        }

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit machidpi",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? DisplayRef else { return }
        guard !hidpi.pending.contains(ref.display.id) else { return }
        if hidpi.sessions[ref.display.id] != nil {
            hidpi.disable(physicalID: ref.display.id)
            var prefs = store.prefs(for: ref.display.uuid) ?? DisplayPrefs(enabled: false, rung: nil)
            prefs.enabled = false
            store.set(prefs, for: ref.display.uuid)
            rebuildMenu()
        } else {
            enableDisplay(ref.display, rung: store.prefs(for: ref.display.uuid)?.rung)
        }
    }

    @objc private func selectRung(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? DisplayRef, let rung = ref.rung else { return }
        if hidpi.setRung(rung, physicalID: ref.display.id) {
            var prefs = store.prefs(for: ref.display.uuid) ?? DisplayPrefs(enabled: true, rung: nil)
            prefs.enabled = true
            prefs.rung = rung
            store.set(prefs, for: ref.display.uuid)
        } else {
            lastErrors[ref.display.uuid] = "could not switch to \(rung.label)"
        }
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            lastErrors["login-item"] = error.localizedDescription
        }
        rebuildMenu()
    }
}

/// Menu item payload (NSMenuItem.representedObject requires a class).
private final class DisplayRef: NSObject {
    let display: PhysicalDisplay
    let rung: Rung?
    init(display: PhysicalDisplay, rung: Rung? = nil) {
        self.display = display
        self.rung = rung
    }
}
