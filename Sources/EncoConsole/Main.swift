import AppKit

@main
struct Main {
    static func main() {
        // _NSAutomaticFocusRing's Swift code segfaults in CLT-built binaries on
        // this OS build; the ring is purely decorative in this app, so disable it.
        UserDefaults.standard.register(defaults: ["NSAutomaticFocusRingEnabled": false])
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Enco Console"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0x1a / 255.0, green: 0x1b / 255.0, blue: 0x1e / 255.0, alpha: 1)
        window.minSize = NSSize(width: 960, height: 700)
        window.contentViewController = ConsoleViewController()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
