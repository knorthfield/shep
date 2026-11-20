import SwiftUI

@main
struct ShepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                menuItems(for: .file)
            }
            CommandGroup(after: .sidebar) {
                menuItems(for: .view)
            }
        }
    }

    private func menuItems(for menu: ShepCommand.Menu) -> some View {
        ForEach(ShepCommand.all.filter { $0.menu == menu }) { command in
            Button(command.title) { command.action(model) }
                .keyboardShortcut(command.shortcut)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: MainWindow?
    private let updateRelauncher = UpdateRelauncher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsKey.registerDefaults()
        // The unit tests run inside the app: do not show the window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let window = MainWindow(model: model)
        window.show()
        model.start()
        self.window = window
        updateRelauncher.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // The user is in front of Shep again: the agents on the screen are seen.
        model.markVisibleAgentsSeen()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
