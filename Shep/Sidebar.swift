import SwiftUI

/// The spaces of each machine, the list of agents, and the links to Settings.
struct Sidebar: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var spaceToRename: LayoutDocument.Space?
    @State private var newName = ""
    @State private var machineError: String?

    var body: some View {
        List(selection: selection) {
            Section {
                spaceRows(onMachine: nil)
            } header: {
                MachineHeader(name: "This Computer", symbol: "desktopcomputer") {
                    headerButton("New Space", symbol: "plus") { model.newSpace() }
                }
            }
            ForEach(model.machines) { machine in
                Section {
                    spaceRows(onMachine: machine.name)
                } header: {
                    MachineHeader(name: machine.name, symbol: "server.rack") {
                        if machine.state == .connected {
                            headerButton("New Space on \(machine.name)", symbol: "plus") { model.newSpace(machine: machine.name) }
                        }
                        headerButton("Pause \(machine.name)", symbol: "pause.fill") { model.pauseMachine(machine) }
                        MachineStateDot(state: machine.state, reason: machine.reason)
                    }
                    .contextMenu {
                        Button("Pause") { model.pauseMachine(machine) }
                    }
                }
            }
            ForEach(model.pausedMachines) { machine in
                Section {
                    Text(model.resumingMachine == machine.name ? "Connecting…" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } header: {
                    MachineHeader(name: machine.name, symbol: "server.rack") {
                        headerButton("Resume \(machine.name)", symbol: "play.fill") { resume(machine) }
                            .disabled(model.resumingMachine != nil)
                    }
                    .contextMenu {
                        Button("Resume") { resume(machine) }
                            .disabled(model.resumingMachine != nil)
                    }
                }
            }
            agentsSection
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .alert("Rename Space", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let spaceToRename { model.rename(spaceToRename, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A space without a name shows the name of its folder.")
        }
        .alert("The Machine Did Not Connect", isPresented: hasMachineError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(machineError ?? "")
        }
    }

    // MARK: Spaces

    private func spaceRows(onMachine machine: String?) -> some View {
        ForEach(model.spaces.filter { $0.machine == machine }) { space in
            HStack(spacing: 8) {
                SpaceBadge(name: model.displayName(of: space), spaceID: space.id)
                Text(model.displayName(of: space))
                    .lineLimit(1)
                Spacer()
                StatusDot(status: model.status(of: space))
            }
            .tag(space.id)
            .contextMenu {
                Button("Rename…") {
                    newName = space.name
                    spaceToRename = space
                }
                Button("Close Space", role: .destructive) { model.close(space) }
            }
        }
    }

    private func headerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(title)
    }

    private func resume(_ machine: Machine) {
        Task { machineError = await model.resumeMachine(machine) }
    }

    // MARK: Agents

    private var agentsSection: some View {
        Section("Agents") {
            let groups = Attention.grouped(model.terminals.ordered)
            if groups.isEmpty {
                Text("No agent status yet. Agents show here when they report their status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            // The ages change with the time, not only with the agents.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ForEach(groups, id: \.status) { group in
                    Text("\(Self.title(of: group.status)) \(group.agents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                    ForEach(group.agents, id: \.terminal.address) { agent in
                        agentRow(agent.terminal, isSubAgent: agent.isSubAgent)
                    }
                }
            }
        }
    }

    private static func title(of status: AgentStatus) -> String {
        switch status {
        case .blocked: "Needs you"
        case .done: "Done"
        case .working: "Working"
        case .idle: "Idle"
        }
    }

    private func agentRow(_ terminal: TerminalRecord, isSubAgent: Bool) -> some View {
        Button {
            model.show(terminal: terminal.address)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agentTitle(terminal))
                        .lineLimit(1)
                    Text([terminal.programName, terminal.machine].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if Attention.isPinned(terminal) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = terminal.statusChangeDate {
                    Text(Attention.age(since: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                StatusDot(status: Attention.status(of: terminal), showsIdle: true)
            }
            .padding(.leading, isSubAgent ? 14 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The selection of the list is the active space: an agent row is a button, not a selection.
        .selectionDisabled()
        .contextMenu {
            Button(Attention.isPinned(terminal) ? "Unpin" : "Pin") { model.togglePin(terminal) }
            Button("Mark as Unread") { model.markUnread(terminal) }
                .disabled(Attention.unreadValue(for: terminal) == nil)
        }
    }

    /// The space of the agent, then what the agent does.
    private func agentTitle(_ terminal: TerminalRecord) -> String {
        let space = model.space(of: terminal).map(model.displayName(of:))
        return [space, terminal.displayName].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.bottom, 4)
            footerButton("Settings", symbol: "gearshape") { openSettings() }
            footerButton("Add Machine", symbol: "plus") {
                model.settingsPane = .machines
                openSettings()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // The symbols have different widths: the titles start at the same place.
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var selection: Binding<String?> {
        Binding { model.activeSpace?.id } set: { model.activeSpaceID = $0 }
    }

    private var isRenaming: Binding<Bool> {
        Binding { spaceToRename != nil } set: { if !$0 { spaceToRename = nil } }
    }

    private var hasMachineError: Binding<Bool> {
        Binding { machineError != nil } set: { if !$0 { machineError = nil } }
    }
}

/// The header of the spaces of one machine: its name, then its buttons.
private struct MachineHeader<Buttons: View>: View {
    let name: String
    let symbol: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(name)
                .lineLimit(1)
            Spacer()
            buttons
        }
    }
}

/// A small circle that shows if the core has a connection to a machine.
private struct MachineStateDot: View {
    let state: Machine.State
    let reason: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help(label)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .connected: .green
        case .connecting: .gray
        case .needsLogin, .unreachable: .red
        }
    }

    private var label: String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .needsLogin: "SSH needs a login. \(reason)"
        case .unreachable: "Not reachable. \(reason)"
        }
    }
}

/// A square with the first letter of a space. A space keeps its colour.
struct SpaceBadge: View {
    private static let colors: [Color] = [.teal, .orange, .blue, .purple, .green, .pink]

    let name: String
    let spaceID: String

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Self.color(for: spaceID), in: .rect(cornerRadius: 5))
            .accessibilityHidden(true)
    }

    /// Not `hashValue`: that changes each time the app starts. This is the FNV-1a hash.
    static func color(for spaceID: String) -> Color {
        let hash = spaceID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

/// A small circle that shows the status of an agent.
struct StatusDot: View {
    let status: AgentStatus?
    /// Shows a ring for an idle agent. Without this, an idle agent shows no circle.
    var showsIdle = false

    var body: some View {
        switch status {
        case .blocked: dot(.red, "Needs you")
        case .done: dot(.green, "Done")
        case .working: dot(.orange, "Working")
        case .idle where showsIdle:
            Circle()
                .strokeBorder(.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Idle")
                .help("Idle")
        case .idle, nil: EmptyView()
        }
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
            .help(label)
    }
}
