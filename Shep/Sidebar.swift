import SwiftUI

/// The spaces of each machine, the list of agents, and the links to Settings.
struct Sidebar: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var spaceToRename: LayoutDocument.Space?
    @State private var newName = ""
    @State private var machineError: String?

    var body: some View {
        // The machines and the agents scroll independently. The user drags the divider between them.
        VSplitView {
            List(selection: selection) {
                Section {
                    MachineHeader(name: "This Computer", symbol: "desktopcomputer") {
                        headerButton("New Space", symbol: "plus") { model.newSpace() }
                    }
                    spaceRows(onMachine: nil)
                }
                // One list for the active and the paused machines: a machine shows one time and keeps its place.
                ForEach(model.sidebarMachines, id: \.machine.name) { entry in
                    if entry.isPaused {
                        pausedSection(entry.machine)
                    } else {
                        activeSection(entry.machine)
                    }
                }
            }
            // Inside the split view, a list does not get the sidebar style by itself.
            .listStyle(.sidebar)
            .frame(minHeight: 80)
            List {
                agentsSection
            }
            .listStyle(.sidebar)
            // Bars, not insets: the rows that scroll under the heading and the footer fade out and do not show through them.
            .safeAreaBar(edge: .top, spacing: 0) { agentsHeading }
            .safeAreaBar(edge: .bottom, spacing: 0) { footer }
            .frame(minHeight: 80)
        }
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

    // MARK: Machines

    private func activeSection(_ machine: Machine) -> some View {
        Section {
            MachineHeader(name: machine.name, symbol: "xserve") {
                if machine.state == .connected {
                    headerButton("New Space on \(machine.name)", symbol: "plus") { model.newSpace(machine: machine.name) }
                }
                headerButton("Pause \(machine.name)", symbol: "pause.fill") { model.pauseMachine(machine) }
                MachineStateDot(state: machine.state, reason: machine.reason)
            }
            .contextMenu {
                Button("Pause") { model.pauseMachine(machine) }
            }
            spaceRows(onMachine: machine.name)
        }
    }

    private func pausedSection(_ machine: Machine) -> some View {
        Section {
            MachineHeader(name: machine.name, symbol: "xserve") {
                headerButton("Resume \(machine.name)", symbol: "play.fill") { resume(machine) }
                    .disabled(model.resumingMachine != nil)
            }
            .contextMenu {
                Button("Resume") { resume(machine) }
                    .disabled(model.resumingMachine != nil)
            }
            Text(model.resumingMachine == machine.name ? "Connecting…" : "Paused")
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectionDisabled()
        }
    }

    // MARK: Spaces

    private func spaceRows(onMachine machine: String?) -> some View {
        ForEach(model.spaces.filter { $0.machine == machine }) { space in
            HStack(spacing: 8) {
                SpaceBadge(name: model.displayName(of: space), spaceID: space.id)
                Text(model.displayName(of: space))
                    // A list row on macOS has a limit of one line.
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                GitCountsLabel(counts: model.gitCounts[space.id])
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
        Section {
            let groups = Attention.grouped(model.terminals.ordered)
            if groups.isEmpty {
                Text("No agent status yet. Agents show here when they report their status.")
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            // The ages change with the time, not only with the agents.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                ForEach(groups, id: \.status) { group in
                    Text("\(Self.title(of: group.status)) \(group.agents.count)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .selectionDisabled()
                    ForEach(group.agents, id: \.terminal.address) { agent in
                        agentRow(agent.terminal, isSubAgent: agent.isSubAgent)
                    }
                }
            }
        }
    }

    /// The heading of the agents. It is not a section header: a section header scrolls away with the rows.
    private var agentsHeading: some View {
        // The same layout as the heading of a machine.
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
            Text("Agents")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            // Each piece of information has its own line. The status is on the first line.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    let names = agentNames(terminal)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        agentLine(names.first ?? "")
                        Spacer(minLength: 0)
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
                                .fixedSize()
                        }
                        StatusDot(status: Attention.status(of: terminal), showsIdle: true)
                    }
                    ForEach(names.dropFirst(), id: \.self) { agentLine($0) }
                    // The program and the machine are on one line.
                    let details = [terminal.programName, terminal.machine].compactMap { $0 }
                    if !details.isEmpty {
                        agentLine(details.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, isSubAgent ? 14 : 0)
            .padding(.vertical, 3)
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
    private func agentNames(_ terminal: TerminalRecord) -> [String] {
        let space = model.space(of: terminal).map(model.displayName(of:))
        return [space, terminal.displayName].compactMap { $0 }
    }

    /// A line of an agent row. A line that is too long for the sidebar wraps: a list row on macOS has a limit of one line.
    private func agentLine(_ text: String) -> some View {
        Text(text)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
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

/// The heading of the spaces of one machine: its name, then its buttons.
/// It is a row, not a section header: a section header has a fixed height, so a long name cannot wrap in it.
private struct MachineHeader<Buttons: View>: View {
    let name: String
    let symbol: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        // The symbol and the buttons stay on the first line of a name that wraps.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
            Text(name)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            buttons
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .selectionDisabled()
    }
}

/// A small symbol that shows if the core has a connection to a machine.
/// Each state has a different shape, so the colour is not the only sign.
private struct MachineStateDot: View {
    let state: Machine.State
    let reason: String

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .help(label)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .connecting: "ellipsis.circle"
        case .needsLogin: "lock.circle.fill"
        case .unreachable: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .connected: .green
        case .connecting: .secondary
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
        Group {
            if let letterSymbol {
                Image(systemName: letterSymbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Self.color(for: spaceID))
                    .font(.system(size: 19))
            } else {
                // SF Symbols has a square only for the letters a to z and the digits.
                Text(name.first.map { String($0).uppercased() } ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Self.color(for: spaceID), in: .rect(cornerRadius: 5))
            }
        }
        .accessibilityHidden(true)
    }

    private var letterSymbol: String? {
        guard let first = name.lowercased().first, first.isASCII, first.isLetter || first.isNumber else { return nil }
        return "\(first).square.fill"
    }

    /// Not `hashValue`: that changes each time the app starts. This is the FNV-1a hash.
    static func color(for spaceID: String) -> Color {
        let hash = spaceID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

/// The number of commits that are not pushed (up, green) and not pulled (down, red).
/// A count of zero does not show.
private struct GitCountsLabel: View {
    let counts: GitCounts?

    var body: some View {
        HStack(spacing: 4) {
            if let counts, counts.ahead > 0 {
                count(counts.ahead, symbol: "arrow.up", color: .green, label: "\(counts.ahead) commits not pushed")
            }
            if let counts, counts.behind > 0 {
                count(counts.behind, symbol: "arrow.down", color: .red, label: "\(counts.behind) commits not pulled")
            }
        }
        .font(.caption)
        .monospacedDigit()
        .fixedSize()
    }

    private func count(_ number: Int, symbol: String, color: Color, label: String) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
            Text(String(number))
        }
        .foregroundStyle(color)
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A small symbol that shows the status of an agent.
struct StatusDot: View {
    let status: AgentStatus?
    /// Shows a ring for an idle agent. Without this, an idle agent shows no symbol.
    var showsIdle = false

    var body: some View {
        switch status {
        case .blocked: symbol("exclamationmark.circle.fill", .red, "Needs you")
        case .done: symbol("checkmark.circle.fill", .green, "Done")
        case .working:
            symbol("progress.indicator", .orange, "Working")
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
        case .idle where showsIdle: symbol("circle", .secondary, "Idle")
        case .idle, nil: EmptyView()
        }
    }

    private func symbol(_ name: String, _ color: Color, _ label: String) -> some View {
        Image(systemName: name)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel(label)
            .help(label)
    }
}
