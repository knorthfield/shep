import SwiftUI

/// The keys of the settings in UserDefaults.
enum SettingsKey {
    /// The path of the `hc` command. Empty: Shep finds it.
    static let hcPath = "HcPath"
    static let playsSounds = "PlaysSounds"
    static let showsNotifications = "ShowsNotifications"
    static let fontSize = "FontSize"

    static let standardFontSize = 13.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [playsSounds: true, showsNotifications: true, fontSize: standardFontSize])
    }
}

struct SettingsView: View {
    let model: AppModel
    @AppStorage(SettingsKey.hcPath) private var hcPath = ""
    @AppStorage(SettingsKey.playsSounds) private var playsSounds = true
    @AppStorage(SettingsKey.showsNotifications) private var showsNotifications = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsKey.standardFontSize
    @State private var newMachineTarget = ""
    @State private var machineError: String?
    @State private var isAddingMachine = false

    var body: some View {
        Form {
            Section {
                Stepper("Font size: \(Int(fontSize)) pt", value: $fontSize, in: 9...24)
            } header: {
                Text("Terminal")
            } footer: {
                Text("Terminals that are open keep their size until Shep starts again.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Play a sound", isOn: $playsSounds)
                Toggle("Show a notification", isOn: $showsNotifications)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Shep alerts you when an agent needs you or stops work. The notification shows only if you do not look at the agent.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(model.machines) { machine in
                    LabeledContent(machine.name) {
                        Text(Self.description(of: machine))
                            .foregroundStyle(machine.state == .connected ? .secondary : .primary)
                        Button("Remove") { model.removeMachine(machine) }
                    }
                }
                LabeledContent("Add a machine") {
                    TextField("user@host", text: $newMachineTarget)
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
            } header: {
                Text("Machines")
            } footer: {
                Text("A machine is a computer that you connect to with SSH, as in `ssh user@host`. It must have herdr-core. Its spaces and agents show in the sidebar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Path of hc", text: $hcPath, prompt: Text("Found automatically"))
            } header: {
                Text("herdr-core")
            } footer: {
                Text("Shep controls herdr-core through its `hc` command. Set the path only if Shep does not find it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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
}
