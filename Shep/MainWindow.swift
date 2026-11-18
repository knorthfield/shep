import AppKit
import SwiftUI

/// Shep's one window.
@MainActor
final class MainWindow {
    private static let autosaveName = "MainWindow"
    private static let firstSize = NSSize(width: 1100, height: 700)

    private let window: NSWindow

    init(model: AppModel) {
        let window = ShepWindow(
            contentRect: NSRect(origin: .zero, size: Self.firstSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.closeTab = { model.closeTab() }
        self.window = window
        window.title = "Shep"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 400)
        let host = NSHostingController(rootView: ContentView(model: model))
        // Lets the SwiftUI toolbar items go into the window's toolbar.
        host.sceneBridgingOptions = [.toolbars]
        // Never `.preferredContentSize`: on macOS 26 it can recurse and crash.
        host.sizingOptions = []
        window.contentViewController = host
        // Setting the view controller sizes the window to its smallest size: set the first size again.
        window.setContentSize(Self.firstSize)
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }
}

/// The Close command of the menu (Command-W) closes the active tab, as in Herdr. The close button closes the window.
private final class ShepWindow: NSWindow {
    /// Closes the active tab. Returns false if there is no tab.
    var closeTab: (() -> Bool)?

    override func performClose(_ sender: Any?) {
        if sender is NSMenuItem, closeTab?() == true { return }
        super.performClose(sender)
    }
}
