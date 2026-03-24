import AppKit
import MarketWatcher
import SwiftUI

@main
struct MarketWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — the floating NSPanel is owned entirely by AppDelegate.
        // An empty Settings scene satisfies the App protocol's scene requirement
        // without producing any visible window. (With .accessory activation
        // policy there is no app menu, so the Settings window is unreachable.)
        Settings { EmptyView() }
    }
}
