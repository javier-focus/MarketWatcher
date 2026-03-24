import AppKit
import MarketWatcher
import SwiftUI

// NSHostingView forwards all mouse events into SwiftUI's responder chain,
// so AppKit's .menu property is never consulted on a right-click.
// Subclassing and overriding rightMouseDown is the only reliable fix.
private final class ContextMenuHostingView<Content: View>: NSHostingView<Content> {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { super.rightMouseDown(with: event); return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// @MainActor is correct here: every NSApplicationDelegate / NSWindowDelegate
// callback is dispatched on the main thread, and MarketViewModel requires it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: - Properties

    // Each panel is fully independent — it owns its own ViewModel and refresh
    // cycle so indexes and intervals can differ between widgets.
    private var panels: [NSPanel] = []

    private let frameKey = "widgetFrame_v6"

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // Double-clicking the .app when a process is already running never launches
    // a second process — macOS always routes back to the existing one and calls
    // this method instead. Creating a new panel here gives users the "new
    // instance" behaviour without requiring `open -n` from the Terminal.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        buildPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Panel construction

    @discardableResult
    private func buildPanel() -> NSPanel {
        // First panel: restore the saved position.
        // Additional panels: cascade 24 pt right/down from the previous one.
        let initialFrame: NSRect = panels.isEmpty
            ? (restoredFrame() ?? NSRect(x: 100, y: 100, width: 344, height: 164))
            : panels.last!.frame.offsetBy(dx: 24, dy: -24)

        let p = NSPanel(
            contentRect: initialFrame,
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        // Sit just above desktop icons but below every normal app window.
        p.level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]

        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate           = false
        p.hasShadow                   = true

        p.styleMask.insert(.fullSizeContentView)
        p.titlebarAppearsTransparent  = true
        p.titleVisibility             = .hidden

        // Hide the three traffic-light buttons completely.
        p.standardWindowButton(.closeButton)?.isHidden      = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden       = true

        p.backgroundColor = .clear
        p.isOpaque        = false

        // Force dark aqua so the Picker dropdown renders with white text on dark
        // backgrounds regardless of the system-wide light/dark setting.
        p.appearance = NSAppearance(named: .darkAqua)
        p.minSize    = NSSize(width: 344, height: 164)
        p.delegate   = self

        // Each panel gets its own ViewModel so index/interval/refresh are independent.
        let viewModel   = MarketViewModel()
        let rootView    = ContentView().environmentObject(viewModel)
        let hostingView = ContextMenuHostingView(rootView: rootView)

        // Right-click anywhere on the widget shows a Quit item.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title:         "Quit MarketWatcher",
            action:        #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        ))
        hostingView.menu = menu

        p.contentView = hostingView
        panels.append(p)
        p.orderFront(nil)
        return p
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        // Persist position only for the primary panel so additional panels
        // don't overwrite the saved frame on every drag.
        guard let panel = notification.object as? NSPanel,
              panel === panels.first else { return }
        saveFrame(panel.frame)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === closed }

        // If the system closed the last panel, reopen one after a short delay
        // so the widget cannot be permanently dismissed without using Quit.
        if panels.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.buildPanel()
            }
        }
    }

    // MARK: - Frame persistence

    /// Returns the last saved NSRect, or nil if no value has been stored yet.
    private func restoredFrame() -> NSRect? {
        guard
            let data  = UserDefaults.standard.data(forKey: frameKey),
            let value = try? NSKeyedUnarchiver.unarchivedObject(
                            ofClass: NSValue.self, from: data)
        else { return nil }
        return value.rectValue
    }

    /// Archives `frame` to Data via NSKeyedArchiver and writes it to UserDefaults.
    private func saveFrame(_ frame: NSRect) {
        guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: NSValue(rect: frame),
                requiringSecureCoding: true)
        else { return }
        UserDefaults.standard.set(data, forKey: frameKey)
    }
}
