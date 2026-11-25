import SwiftUI

/// One command of Shep. The menu bar and the command palette show the same commands. The keys are those of Herdr.
struct ShepCommand: Identifiable {
    enum Menu {
        case file
        case view
    }

    let title: String
    let menu: Menu
    var shortcut: KeyboardShortcut?
    let action: @MainActor (AppModel) -> Void

    var id: String { title }

    /// The shortcut as the menu shows it, for example `⇧⌘D`.
    var shortcutText: String {
        guard let shortcut else { return "" }
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        let key: String = switch shortcut.key {
        case .return: "↩"
        case .leftArrow: "←"
        case .rightArrow: "→"
        default: String(shortcut.key.character).uppercased()
        }
        return text + key
    }

    static let all: [ShepCommand] = [
        ShepCommand(title: "New Tab", menu: .file, shortcut: .init("t")) { $0.newTab() },
        ShepCommand(title: "New Space", menu: .file, shortcut: .init("n")) { $0.newSpace() },
        ShepCommand(title: "New Space in Folder…", menu: .file, shortcut: .init("n", modifiers: [.command, .shift])) { $0.newSpaceInFolder() },
        // Command-W is the Close command of the window: it closes the active tab.
        ShepCommand(title: "Close Tab", menu: .file) { $0.closeTab() },
        ShepCommand(title: "Close Pane", menu: .file, shortcut: .init("w", modifiers: [.command, .shift])) { $0.closePane() },
        ShepCommand(title: "Command Palette…", menu: .view, shortcut: .init("p", modifiers: [.command, .shift])) { $0.isPaletteVisible = true },
        ShepCommand(title: "Show or Hide Sidebar", menu: .view, shortcut: .init("b")) { $0.isSidebarVisible.toggle() },
        ShepCommand(title: "Filter Spaces", menu: .view, shortcut: .init("f", modifiers: [.command, .option])) {
            $0.isSidebarVisible = true
            $0.isSidebarFilterFocused = true
        },
        ShepCommand(title: "Split Right", menu: .view, shortcut: .init("d")) { $0.split(.row) },
        ShepCommand(title: "Split Down", menu: .view, shortcut: .init("d", modifiers: [.command, .shift])) { $0.split(.column) },
        ShepCommand(title: "Zoom Pane", menu: .view, shortcut: .init(.return, modifiers: [.command, .shift])) { $0.toggleZoom() },
        ShepCommand(title: "Next Pane", menu: .view, shortcut: .init(.rightArrow, modifiers: [.command, .option])) { $0.focusPane(offset: 1) },
        ShepCommand(title: "Previous Pane", menu: .view, shortcut: .init(.leftArrow, modifiers: [.command, .option])) { $0.focusPane(offset: -1) },
        ShepCommand(title: "Next Tab", menu: .view, shortcut: .init("]", modifiers: [.command, .shift])) { $0.selectTab(offset: 1) },
        ShepCommand(title: "Previous Tab", menu: .view, shortcut: .init("[", modifiers: [.command, .shift])) { $0.selectTab(offset: -1) },
        ShepCommand(title: "Next Space", menu: .view, shortcut: .init("]", modifiers: [.command, .option])) { $0.selectSpace(offset: 1) },
        ShepCommand(title: "Previous Space", menu: .view, shortcut: .init("[", modifiers: [.command, .option])) { $0.selectSpace(offset: -1) },
        ShepCommand(title: "Next Agent", menu: .view, shortcut: .init("]")) { $0.selectAgent(offset: 1) },
        ShepCommand(title: "Previous Agent", menu: .view, shortcut: .init("[")) { $0.selectAgent(offset: -1) },
    ] + (0..<9).map { index in
        ShepCommand(title: "Tab \(index + 1)", menu: .view, shortcut: .init(KeyEquivalent(Character("\(index + 1)")))) { $0.selectTab(at: index) }
    } + (0..<9).map { index in
        ShepCommand(title: "Space \(index + 1)", menu: .view, shortcut: .init(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)) { $0.selectSpace(at: index) }
    }
}

/// A list of all commands with a search field.
struct CommandPalette: View {
    let model: AppModel
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool

    private var matches: [ShepCommand] {
        search.isEmpty ? ShepCommand.all : ShepCommand.all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Command", text: $search)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($isSearchFocused)
                .onSubmit {
                    if let first = matches.first { run(first) }
                }
            Divider()
            List(matches) { command in
                Button {
                    run(command)
                } label: {
                    HStack {
                        Text(command.title)
                        Spacer()
                        Text(command.shortcutText)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 440, height: 360)
        .onAppear { isSearchFocused = true }
        .onExitCommand { model.isPaletteVisible = false }
    }

    private func run(_ command: ShepCommand) {
        model.isPaletteVisible = false
        command.action(model)
    }
}
