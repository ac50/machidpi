import AppKit

if CommandLine.arguments.dropFirst().first == "probe" {
    exit(runProbe())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
