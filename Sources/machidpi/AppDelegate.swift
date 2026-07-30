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
        let externals = Displays.external(excluding: hidpi.virtualIDs)
        let presentIDs = Set(externals.map(\.id))

        for physicalID in hidpi.sessions.keys where !presentIDs.contains(physicalID) {
            hidpi.disable(physicalID: physicalID)
        }
        for display in externals
        where hidpi.sessions[display.id] == nil
            && store.prefs(for: display.uuid)?.enabled == true
        {
            enableDisplay(display, rung: store.prefs(for: display.uuid)?.rung)
        }
        rebuildMenu()
    }

    private func enableDisplay(_ display: PhysicalDisplay, rung: Rung?) {
        lastErrors[display.uuid] = nil
        hidpi.enable(display, rung: rung) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let current = self.hidpi.sessions[display.id]?.currentRung
                self.store.set(DisplayPrefs(enabled: true, rung: current), for: display.uuid)
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
                    let item = NSMenuItem(title: rung.label,
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
            store.set(DisplayPrefs(enabled: true, rung: rung), for: ref.display.uuid)
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
