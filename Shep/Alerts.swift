import AppKit
import UserNotifications

/// Tells the user that an agent needs a person or stopped work: a sound, and a notification if the user does not look at the agent.
@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let terminalKey = "terminal"

    /// The user clicked the notification of a terminal.
    var onOpen: ((_ address: String) -> Void)?

    func present(_ alert: Attention.Alert, for terminal: TerminalRecord, isLooking: Bool) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SettingsKey.playsSounds) {
            NSSound(named: alert == .blocked ? "Ping" : "Glass")?.play()
        }
        guard !isLooking, defaults.bool(forKey: SettingsKey.showsNotifications) else { return }
        let content = UNMutableNotificationContent()
        content.title = terminal.displayName
        content.body = alert == .blocked ? "The agent needs you." : "The agent stopped work."
        content.userInfo = [Self.terminalKey: terminal.address]
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            // The same identifier replaces an older notification of the same terminal.
            try? await center.add(UNNotificationRequest(identifier: terminal.address, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let address = response.notification.request.content.userInfo[Self.terminalKey] as? String else { return }
        await MainActor.run {
            NSApp.activate()
            onOpen?(address)
        }
    }
}
