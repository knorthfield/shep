import SwiftUI

/// The list of spaces and the list of agents.
struct Sidebar: View {
    @Bindable var model: AppModel
    @State private var spaceToRename: LayoutDocument.Space?
    @State private var newName = ""

    var body: some View {
        List(selection: selection) {
            Section("Spaces") {
                ForEach(model.spaces) { space in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.displayName(of: space))
                            if let machine = space.machine {
                                Text(machine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            if !model.agents.isEmpty {
                Section("Agents") {
                    ForEach(model.agents, id: \.terminal.address) { agent in
                        agentRow(agent.terminal, isSubAgent: agent.isSubAgent)
                    }
                }
            }
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
    }

    private func agentRow(_ terminal: TerminalRecord, isSubAgent: Bool) -> some View {
        Button {
            model.show(terminal: terminal.address)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(terminal.displayName)
                        .lineLimit(1)
                    Text([terminal.statusApp, terminal.machine].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if Attention.isPinned(terminal) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                StatusDot(status: Attention.status(of: terminal))
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

    private var selection: Binding<String?> {
        Binding { model.activeSpace?.id } set: { model.activeSpaceID = $0 }
    }

    private var isRenaming: Binding<Bool> {
        Binding { spaceToRename != nil } set: { if !$0 { spaceToRename = nil } }
    }
}

/// A small circle that shows the status of an agent. Idle agents show no circle.
struct StatusDot: View {
    let status: AgentStatus?

    var body: some View {
        switch status {
        case .blocked: dot(.red, "Needs you")
        case .done: dot(.green, "Done")
        case .working: dot(.orange, "Working")
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
