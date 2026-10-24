import AppKit
import MacHiDPIKit
import os
import ServiceManagement

/// `log stream --predicate 'subsystem == "io.github.ac50.machidpi"'`
private let logger = Logger(subsystem: "io.github.ac50.machidpi", category: "display")

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

    /// UUIDs of displays that currently occupy a place in the arrangement.
    private var lastArrangedSet: Set<String> = []

    /// Automatic re-enables left per display; manual toggles and replugs
    /// reset it.
    private var enableRetries = RetryBudget(limit: 3)

    /// Make reality match preferences: tear down sessions whose physical
    /// display vanished; enable remembered displays that (re)appeared.
    private func reconcile() {
        let externals = Displays.external(excluding: hidpi.virtualIDs)
        let presentIDs = Set(externals.map(\.id))
        enableRetries.keep(only: Set(externals.map(\.uuid)))

        for physicalID in hidpi.sessions.keys where !presentIDs.contains(physicalID) {
            logger.info("panel \(physicalID, privacy: .public) gone, tearing down")
            hidpi.disable(physicalID: physicalID)
        }
        for display in externals
        where hidpi.sessions[display.id] == nil
            && !hidpi.pending.contains(display.id)
            && store.prefs(for: display.uuid)?.enabled == true
            && enableRetries.allows(display.uuid)
        {
            enableDisplay(display, rung: store.prefs(for: display.uuid)?.rung)
        }

        // Wake, lid and standby transitions take several reconfigurations to
        // finish; touching the layout before every mirror is back fights
        // WindowServer. A later event re-runs this once things settle.
        guard layoutSettled() else {
            logger.info("layout not settled (enable in flight or mirror missing), waiting")
            // Whatever happened meanwhile counts as a topology change: the
            // next settled pass restores instead of recording a re-tile.
            lastArrangedSet = []
            rebuildMenu()
            return
        }

        // Topology change (lid open/close, plug/unplug): macOS repositions
        // displays on such transitions, so re-apply the saved layout. On a
        // stable topology the event was the user dragging — record it.
        let arrangedSet = Set(Displays.onlineIDs()
            .filter { !Displays.isMirrorSlave($0) }
            .compactMap(Displays.uuidString(for:)))
        if arrangedSet != lastArrangedSet {
            lastArrangedSet = arrangedSet
            if !hidpi.sessions.isEmpty {
                restoreArrangement()
            }
        } else {
            persistOrigins()
        }
        rebuildMenu()
    }

    /// No enable in flight and every session's panel still mirrors its
    /// virtual display.
    private func layoutSettled() -> Bool {
        hidpi.pending.isEmpty && hidpi.sessions.values.allSatisfy {
            CGDisplayMirrorsDisplay($0.physical.id) == $0.virtualID
        }
    }

    /// Origins of the displays that occupy a place in the arrangement (mirror
    /// slaves follow their master), keyed by UUID.
    private func arrangedOrigins() -> (origins: [String: DisplayOrigin],
                                       ids: [String: CGDirectDisplayID])
    {
        var origins: [String: DisplayOrigin] = [:]
        var ids: [String: CGDirectDisplayID] = [:]
        for id in Displays.onlineIDs() where !Displays.isMirrorSlave(id) {
            guard let uuid = Displays.uuidString(for: id) else { continue }
            let origin = CGDisplayBounds(id).origin
            origins[uuid] = DisplayOrigin(x: Int(origin.x), y: Int(origin.y))
            ids[uuid] = id
        }
        return (origins, ids)
    }

    /// Remember where the user placed every display while HiDPI is active
    /// (arrangement changes arrive as reconfiguration events). Skipped until
    /// the layout has settled so transient layouts are never recorded.
    private func persistOrigins() {
        guard layoutSettled(), !hidpi.sessions.isEmpty else { return }
        let panels = Set(hidpi.sessions.values.map(\.physical.uuid))
        // A lone display always sits at (0,0); recording that transient
        // state (clamshell) would corrupt the remembered multi-display
        // layout, so only snapshot real arrangements.
        guard let snapshot = Arrangement.snapshot(of: arrangedOrigins().origins,
                                                  excluding: panels)
        else { return }

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

        let topology = Arrangement.topologyKey(Set(snapshot.keys))
        if store.arrangement(for: topology) != snapshot {
            store.setArrangement(snapshot, for: topology)
        }
    }

    /// Quartz auto-repositions every display we did not explicitly place
    /// when the mirror forms — and the virtual display's point size differs
    /// from the physical's, so neighbours get repacked. Re-apply the layout
    /// saved for exactly this set of displays, in one transaction.
    private func restoreArrangement() {
        guard layoutSettled() else { return }
        let (current, ids) = arrangedOrigins()
        let topology = Arrangement.topologyKey(Set(current.keys))
        guard let saved = store.arrangement(for: topology) else { return }
        var moves: [(CGDirectDisplayID, DisplayOrigin)] = []
        for (uuid, target) in Arrangement.restoreMoves(current: current, saved: saved) {
            guard let id = ids[uuid] else { continue }
            moves.append((id, target))
        }
        guard !moves.isEmpty else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for (id, target) in moves {
            CGConfigureDisplayOrigin(config, id, Int32(target.x), Int32(target.y))
        }
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        logger.info("restored \(moves.count, privacy: .public) origin(s): CGError \(result.rawValue, privacy: .public)")
    }

    /// The built-in display's current "looks like" size, remembered so the
    /// matching rung stays available in clamshell mode.
    private func builtinRung() -> Rung? {
        if let live = Displays.builtinLooksLike() {
            if store.builtinLooksLike != live { store.builtinLooksLike = live }
            return live
        }
        return store.builtinLooksLike
    }

    private func enableDisplay(_ display: PhysicalDisplay, rung: Rung?) {
        lastErrors[display.uuid] = nil
        let saved = store.prefs(for: display.uuid)
        // Alone (lid closed) the virtual display lands at (0,0) anyway;
        // requesting a saved side-by-side origin only forces a re-tile.
        let alone = !Displays.onlineIDs().contains {
            $0 != display.id && !Displays.isMirrorSlave($0)
        }
        let origin = alone ? nil : saved.flatMap { prefs in
            prefs.originX.flatMap { x in prefs.originY.map { y in
                CGPoint(x: Double(x), y: Double(y))
            } }
        }
        hidpi.enable(display, rung: rung, origin: origin,
                     builtinRung: builtinRung()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                logger.info("enabled HiDPI on \(display.name, privacy: .public)")
                self.enableRetries.reset(display.uuid)
                var prefs = self.store.prefs(for: display.uuid)
                    ?? DisplayPrefs(enabled: true, rung: nil)
                prefs.enabled = true
                prefs.rung = self.hidpi.sessions[display.id]?.currentRung
                self.store.set(prefs, for: display.uuid)
                // Nothing can overwrite the saved layout meanwhile: recording
                // waits for the layout to settle and is kept per display set.
                self.restoreArrangement()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.restoreArrangement()
                    self?.persistOrigins()
                }
            case .failure(let error):
                logger.error("enable failed on \(display.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.enableRetries.recordFailure(display.uuid)
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
            // Mixed: wanted on, but enabling keeps failing — a click stops it.
            let wanted = store.prefs(for: display.uuid)?.enabled == true
            toggle.state = session != nil ? .on
                : (wanted && lastErrors[display.uuid] != nil ? .mixed : .off)
            toggle.representedObject = DisplayRef(display: display)
            menu.addItem(toggle)

            if let error = lastErrors[display.uuid] {
                menu.addItem(disabledItem("⚠︎ \(error)"))
            }
            if let session, hidpi.pending.isEmpty,
               CGDisplayMirrorsDisplay(display.id) != session.virtualID
            {
                menu.addItem(disabledItem("⚠︎ mirror lost — turn Enable HiDPI off and on"))
            }

            if let session {
                for rung in session.ladder {
                    let exact = Scaling.isPixelExact(rung,
                                                     panelWidth: display.pixelWidth,
                                                     panelHeight: display.pixelHeight)
                    var title = rung.label
                    if rung == session.builtinRung { title += "  (same as MacBook)" }
                    if exact { title += "  ✦" }
                    let item = NSMenuItem(title: title,
                                          action: #selector(selectRung(_:)), keyEquivalent: "")
                    item.target = self
                    item.state = rung == session.currentRung ? .on : .off
                    item.indentationLevel = 1
                    item.representedObject = DisplayRef(display: display, rung: rung)
                    menu.addItem(item)
                }

                // macOS bug (BetterDisplay #144): Spaces gestures only work
                // on the mirror set that holds the main display. Toggle:
                // checked = this display is main; click again to hand main
                // back to the built-in (or first other) display.
                let mainItem = NSMenuItem(
                    title: "Use as Main Display (fixes Spaces swipes)",
                    action: #selector(toggleMainDisplay(_:)),
                    keyEquivalent: ""
                )
                mainItem.target = self
                mainItem.state = CGDisplayIsMain(session.virtualID) != 0 ? .on : .off
                mainItem.indentationLevel = 1
                mainItem.representedObject = DisplayRef(display: display)
                menu.addItem(mainItem)
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
        } else if lastErrors[ref.display.uuid] != nil,
                  var prefs = store.prefs(for: ref.display.uuid), prefs.enabled
        {
            // Failing display: switch it off for good (no retries, not even at
            // next login); the next click is an explicit retry.
            prefs.enabled = false
            store.set(prefs, for: ref.display.uuid)
            lastErrors[ref.display.uuid] = nil
            rebuildMenu()
        } else {
            enableRetries.reset(ref.display.uuid)  // an explicit retry always runs
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

    /// Toggle which display is main, preserving the relative arrangement.
    /// Checked → the virtual display becomes main (works around the macOS
    /// bug where Spaces gestures ignore secondary mirror sets); unchecked →
    /// main goes back to the built-in (or first other) display.
    @objc private func toggleMainDisplay(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? DisplayRef,
              let session = hidpi.sessions[ref.display.id] else { return }

        let target: CGDirectDisplayID
        if CGDisplayIsMain(session.virtualID) != 0 {
            let others = Displays.onlineIDs().filter {
                !Displays.isMirrorSlave($0) && $0 != session.virtualID
            }
            guard let fallback = others.first(where: { CGDisplayIsBuiltin($0) != 0 })
                ?? others.first
            else { return }  // nothing to hand main back to
            target = fallback
        } else {
            target = session.virtualID
        }

        let anchor = CGDisplayBounds(target).origin
        guard anchor.x != 0 || anchor.y != 0 else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for id in Displays.onlineIDs() where !Displays.isMirrorSlave(id) {
            let origin = CGDisplayBounds(id).origin
            CGConfigureDisplayOrigin(config, id,
                                     Int32(origin.x - anchor.x), Int32(origin.y - anchor.y))
        }
        if CGCompleteDisplayConfiguration(config, .forSession) == .success {
            persistOrigins()
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
