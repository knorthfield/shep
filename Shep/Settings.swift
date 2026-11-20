import SwiftUI

/// The keys of the settings in UserDefaults.
enum SettingsKey {
    /// The path of the `hc` command. Empty: Shep finds it.
    static let hcPath = "HcPath"
    static let playsSounds = "PlaysSounds"
    static let showsNotifications = "ShowsNotifications"
    static let fontSize = "FontSize"
    /// The font family of the terminals. Empty: the monospaced font of macOS.
    static let fontName = "FontName"
    static let pausedMachines = "PausedMachines"

    static let standardFontSize = 13.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [playsSounds: true, showsNotifications: true, fontSize: standardFontSize])
    }
}

/// The panes of the Settings window.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case terminal = "Terminal"
    case alerts = "Alerts"
    case machines = "Machines"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .terminal: "terminal"
        case .alerts: "bell.badge"
        case .machines: "server.rack"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .terminal: .indigo
        case .alerts: .red
        case .machines: .blue
        }
    }
}

/// The Settings window: a list of panes at the side, as in System Settings.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selection) { pane in
                Label {
                    Text(pane.rawValue)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(pane.color.gradient, in: .rect(cornerRadius: 5))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form {
                switch model.settingsPane {
                case .general: GeneralSettings()
                case .terminal: TerminalSettings()
                case .alerts: AlertSettings()
                case .machines: MachineSettings(model: model)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model.settingsPane.rawValue)
        }
        .frame(width: 700, height: 440)
    }

    /// The list can have no selection for a moment: the pane stays.
    private var selection: Binding<SettingsPane?> {
        Binding { model.settingsPane } set: { if let pane = $0 { model.settingsPane = pane } }
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.hcPath) private var hcPath = ""

    var body: some View {
        Section {
            TextField("Path of hc", text: $hcPath, prompt: Text("Found automatically"))
        } header: {
            Text("herdr-core")
        } footer: {
            Text("Shep controls herdr-core through its `hc` command. Set the path only if Shep does not find it.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TerminalSettings: View {
    /// The font families where each character has the same width.
    private static let fixedWidthFamilies = NSFontManager.shared.availableFontFamilies.filter { family in
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)?.isFixedPitch == true
    }

    @AppStorage(SettingsKey.fontName) private var fontName = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsKey.standardFontSize

    var body: some View {
        Section {
            Picker("Font", selection: $fontName) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(Self.fixedWidthFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper("Font size: \(Int(fontSize)) pt", value: $fontSize, in: 9...24)
        } footer: {
            Text("Terminals that are open keep their font until Shep starts again.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AlertSettings: View {
    @AppStorage(SettingsKey.playsSounds) private var playsSounds = true
    @AppStorage(SettingsKey.showsNotifications) private var showsNotifications = true

    var body: some View {
        Section {
            Toggle("Play a sound", isOn: $playsSounds)
            Toggle("Show a notification", isOn: $showsNotifications)
        } footer: {
            Text("Shep alerts you when an agent needs you or stops work. The notification shows only if you do not look at the agent.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MachineSettings: View {
    let model: AppModel
    @State private var newMachineTarget = ""
    @State private var machineError: String?
    @State private var isAddingMachine = false

    var body: some View {
        Section {
            ForEach(model.machines) { machine in
                LabeledContent(machine.name) {
                    Text(Self.description(of: machine))
                        .foregroundStyle(machine.state == .connected ? .secondary : .primary)
                    Button("Pause") { model.pauseMachine(machine) }
                    Button("Remove") { model.removeMachine(machine) }
                }
            }
            ForEach(model.pausedMachines) { machine in
                LabeledContent(machine.name) {
                    Text(model.resumingMachine == machine.name ? "Connecting…" : "Paused")
                        .foregroundStyle(.secondary)
                    Button("Resume") { resume(machine) }
                        .disabled(model.resumingMachine != nil)
                    Button("Remove") { model.removeMachine(machine) }
                }
            }
            LabeledContent("Add a machine") {
                TextField("SSH target", text: $newMachineTarget, prompt: Text("user@host"))
                    .labelsHidden()
                    .frame(width: 180)
                    .onSubmit(addMachine)
                Button("Add", action: addMachine)
                    .disabled(newMachineTarget.isEmpty || isAddingMachine)
            }
            if let machineError {
                Text(machineError)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("A machine is a computer that you connect to with SSH, as in `ssh user@host`. It must have herdr-core. Its spaces and agents show in the sidebar. Pause a machine to stop the connection to it: its terminals continue to run, and they show again when you resume it.")
                .foregroundStyle(.secondary)
        }
    }

    private static func description(of machine: Machine) -> String {
        switch machine.state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .needsLogin: "SSH needs a login. \(machine.reason)"
        case .unreachable: "Not reachable. \(machine.reason)"
        }
    }

    private func addMachine() {
        guard !newMachineTarget.isEmpty else { return }
        isAddingMachine = true
        machineError = nil
        Task {
            machineError = await model.addMachine(target: newMachineTarget)
            if machineError == nil { newMachineTarget = "" }
            isAddingMachine = false
        }
    }

    private func resume(_ machine: Machine) {
        machineError = nil
        Task { machineError = await model.resumeMachine(machine) }
    }
}
