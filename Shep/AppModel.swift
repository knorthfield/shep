import AppKit
import Observation
import os

/// The state of the app: the connection to herdr-core, the layout, and what this window shows.
@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case connecting
        case connected
        /// The `hc` command is not on this Mac.
        case hcNotFound
        case failed(message: String)
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shep", category: "AppModel")
    private static let machinePollInterval = Duration.milliseconds(2500)
    private static let gitPollInterval = Duration.seconds(10)

    let terminals = TerminalStore()
    let layout = LayoutStore()
    private(set) var connectionState = ConnectionState.connecting
    private(set) var connection: CoreConnection?
    private(set) var machines: [Machine] = []
    /// Machines that the core does not connect to until the user resumes them. The core cannot pause a machine,
    /// thus Shep removes it from the core and keeps how to add it again.
    private(set) var pausedMachines: [Machine] = AppModel.storedPausedMachines() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(pausedMachines), forKey: SettingsKey.pausedMachines) }
    }
    /// The names of the machines that show the pause controls. The user selects them in Settings.
    private(set) var pausableMachines: Set<String> = AppModel.storedPausableMachines() {
        didSet { UserDefaults.standard.set(pausableMachines.sorted(), forKey: SettingsKey.pausableMachines) }
    }
    /// The machines that the sidebar shows: those of the core and the paused ones.
    var sidebarMachines: [(machine: Machine, isPaused: Bool)] {
        Machine.sidebarList(active: machines, paused: pausedMachines)
    }
    /// The commits that are not pushed and not pulled in the folder of each space, by space id.
    private(set) var gitCounts: [String: GitCounts] = [:]
    /// The name of the paused machine that Shep connects to again now.
    private(set) var resumingMachine: String?
    /// The pane that the Settings window shows.
    var settingsPane = SettingsPane.general
    var isSidebarVisible = true
    var isPaletteVisible = false
    /// The filter field of the sidebar has the keyboard.
    var isSidebarFilterFocused = false
    @ObservationIgnored private let alerts = Alerts()

    /// The space that the window shows. Nil or not found: the first space.
    var activeSpaceID: String? = UserDefaults.standard.string(forKey: ViewStateKey.activeSpace) {
        didSet { UserDefaults.standard.set(activeSpaceID, forKey: ViewStateKey.activeSpace) }
    }
    /// The tab that each space shows, by space id.
    private var activeTabIDs = UserDefaults.standard.dictionary(forKey: ViewStateKey.activeTabs) as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(activeTabIDs, forKey: ViewStateKey.activeTabs) }
    }
    /// The pane that has the keyboard in each tab, by tab id.
    private var focusedPaneIDs: [String: String] = [:]
    /// The pane that fills each zoomed tab, by tab id.
    private var zoomedPaneIDs: [String: String] = [:]

    @ObservationIgnored private var retryDelay = Duration.seconds(1)
    @ObservationIgnored private var sessions: [String: TerminalSession] = [:]

    func start() {
        alerts.onOpen = { [weak self] in self?.show(terminal: $0) }
        Task { await connect() }
    }

    // MARK: What the window shows

    var spaces: [LayoutDocument.Space] { layout.spaces }

    var activeSpace: LayoutDocument.Space? {
        spaces.first { $0.id == activeSpaceID } ?? spaces.first
    }

    var activeTab: LayoutDocument.Tab? {
        guard let space = activeSpace else { return nil }
        return space.tabs.first { $0.id == activeTabIDs[space.id] } ?? space.tabs.first
    }

    /// The pane that has the keyboard in the active tab.
    var focusedPaneID: String? {
        guard let tab = activeTab else { return nil }
        let panes = tab.root.terminalPaneIDs
        return focusedPaneIDs[tab.id].flatMap { panes.contains($0) ? $0 : nil } ?? panes.first
    }

    /// The pane that fills the active tab, if the tab is zoomed.
    var zoomedPane: LayoutDocument.Pane? {
        guard let tab = activeTab, let paneID = zoomedPaneIDs[tab.id], let address = tab.root.address(ofPane: paneID) else { return nil }
        return .terminal(id: paneID, address: address)
    }

    /// The name of a space: its name, or the last part of the folder where its first terminal is now,
    /// or of the folder where the space was made. This is the rule of Herdr.
    func displayName(of space: LayoutDocument.Space) -> String {
        if !space.name.isEmpty { return space.name }
        let folder = folder(of: space)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if folder.isEmpty || folder == home { return "~" }
        return URL(fileURLWithPath: folder).lastPathComponent
    }

    /// The name of a tab: its name, or the name of its first terminal, or its number.
    /// The folder where the first terminal of a space is now, or the folder where the space was made.
    private func folder(of space: LayoutDocument.Space) -> String {
        let liveFolder = space.tabs.lazy.flatMap(\.terminals)
            .compactMap { self.terminals.terminals[$0]?.workingFolder }.first { !$0.isEmpty }
        return liveFolder ?? space.folder
    }

    func displayName(of tab: LayoutDocument.Tab, in space: LayoutDocument.Space) -> String {
        if !tab.name.isEmpty { return tab.name }
        if let terminal = tab.terminals.first.flatMap({ terminals.terminals[$0] }) { return terminal.displayName }
        return String((space.tabs.firstIndex(of: tab) ?? 0) + 1)
    }

    /// The session that shows a terminal. Shep makes it the first time and keeps it, so that the terminal stays attached.
    func session(for address: String) -> TerminalSession? {
        if let session = sessions[address] { return session }
        guard let connection, let session = TerminalSession(address: address, connection: connection) else { return nil }
        session.onBecameFocused = { [weak self] in self?.terminalDidGetFocus(address) }
        sessions[address] = session
        return session
    }

    /// Gives the keyboard to the focused pane of the active tab.
    func focusActivePane() {
        guard let tab = activeTab, let paneID = focusedPaneID, let address = tab.root.address(ofPane: paneID),
              let view = sessions[address]?.view else { return }
        view.window?.makeFirstResponder(view)
    }

    private func terminalDidGetFocus(_ address: String) {
        guard let tab = activeTab, let paneID = tab.root.terminalPaneIDs.first(where: { tab.root.address(ofPane: $0) == address }) else { return }
        focusedPaneIDs[tab.id] = paneID
    }

    // MARK: Agents

    /// The terminals whose programs report a status, in the order of the sidebar.
    var agents: [(terminal: TerminalRecord, isSubAgent: Bool)] {
        Attention.ordered(terminals.ordered)
    }

    /// The space that has a terminal.
    func space(of terminal: TerminalRecord) -> LayoutDocument.Space? {
        spaces.first { $0.tabs.contains { $0.terminals.contains(terminal.address) } }
    }

    /// The most important status of the agents of a space.
    func status(of space: LayoutDocument.Space) -> AgentStatus? {
        Attention.rollup(space.tabs.flatMap(\.terminals).map { terminals.terminals[$0].flatMap(Attention.status(of:)) })
    }

    /// The terminals that are on the screen now.
    private var visibleTerminals: [String] {
        zoomedPane?.terminals ?? activeTab?.terminals ?? []
    }

    /// Writes that a person saw the agents on the screen, if Shep is the app in front. All clients of Herdr share this.
    func markVisibleAgentsSeen() {
        guard NSApp.isActive else { return }
        for terminal in visibleTerminals.compactMap({ terminals.terminals[$0] }) where terminal.statusWord != nil {
            if let value = Attention.seenValueToWrite(for: terminal) { setLabel(Attention.seenLabel, value, on: terminal) }
        }
    }

    func togglePin(_ terminal: TerminalRecord) {
        // An empty value removes the label.
        setLabel(Attention.pinnedLabel, Attention.isPinned(terminal) ? "" : "1", on: terminal)
    }

    func markUnread(_ terminal: TerminalRecord) {
        if let value = Attention.unreadValue(for: terminal) { setLabel(Attention.seenLabel, value, on: terminal) }
    }

    /// Shows the agent after the agent on the screen (`1`) or before it (`-1`).
    func selectAgent(offset: Int) {
        let addresses = agents.map(\.terminal.address)
        guard !addresses.isEmpty else { return }
        let focused = activeTab.flatMap { tab in focusedPaneID.flatMap { tab.root.address(ofPane: $0) } }
        let index = focused.flatMap { addresses.firstIndex(of: $0) }.map { $0 + offset } ?? 0
        show(terminal: addresses[(index + addresses.count) % addresses.count])
    }

    private func setLabel(_ label: String, _ value: String, on terminal: TerminalRecord) {
        Task {
            _ = try? await connection?.call("terminal.label", ["terminal": .string(terminal.address), "labels": [label: .string(value)]])
        }
    }

    // MARK: Machines

    /// Adds a machine by its SSH target. Returns the error, or nil if the machine was added.
    func addMachine(target: String) async -> CoreError? {
        await addMachine(["target": .string(Machine.target(fromInput: target))])
    }

    private func addMachine(_ parameters: JSONValue) async -> CoreError? {
        guard let connection else { return CoreError(message: "Shep has no connection to herdr-core.") }
        do {
            _ = try await connection.call("machine.add", parameters, timeout: .seconds(60))
            return nil
        } catch {
            return error as? CoreError ?? CoreError(message: error.localizedDescription)
        }
    }

    /// Copies the hc of this Mac to a machine that has none, then adds the machine. The core cannot do this,
    /// thus the `hc` command does it. Returns the error text, or nil if the machine was added.
    func installHcAndAddMachine(target: String) async -> String? {
        guard let hc = HcBinary.find(configuredPath: UserDefaults.standard.string(forKey: SettingsKey.hcPath)) else {
            return "Shep did not find hc on this Mac."
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = hc
        process.arguments = ["machine", "add", "--json", "--install", "--", Machine.target(fromInput: target)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return error.localizedDescription }
        let reading = output.fileHandleForReading
        let printed = await Task.detached { reading.readDataToEndOfFile() }.value
        if let connection { await readMachines(on: connection) }
        return HcBinary.machineAddError(inOutput: printed)
    }

    func removeMachine(_ machine: Machine) {
        pausedMachines.removeAll { $0.name == machine.name }
        pausableMachines.remove(machine.name)
        Task { _ = try? await connection?.call("machine.rm", ["machine": .string(machine.name)]) }
    }

    /// Stops the connection to a machine. Its terminals continue to run there.
    func pauseMachine(_ machine: Machine) {
        guard let connection, !pausedMachines.contains(where: { $0.name == machine.name }) else { return }
        pausedMachines.append(machine)
        Task { _ = try? await connection.call("machine.rm", ["machine": .string(machine.name)]) }
    }

    /// Connects to a paused machine again. Returns the error text, or nil if the machine was added.
    func resumeMachine(_ machine: Machine) async -> String? {
        resumingMachine = machine.name
        defer { resumingMachine = nil }
        let error = await addMachine(machine.addParameters)
        if error == nil {
            // Read the list first: if not, the machine is in no list until the next poll and goes out of the sidebar.
            if let connection { await readMachines(on: connection) }
            pausedMachines.removeAll { $0.name == machine.name }
        }
        return error?.text
    }

    /// Shows or hides the pause controls of a machine.
    func setCanPause(_ canPause: Bool, machine name: String) {
        if canPause { pausableMachines.insert(name) } else { pausableMachines.remove(name) }
    }

    /// Before this setting, each machine had the pause controls: a machine that is paused then keeps them.
    private static func storedPausableMachines() -> Set<String> {
        guard let names = UserDefaults.standard.stringArray(forKey: SettingsKey.pausableMachines) else {
            return Set(storedPausedMachines().map(\.name))
        }
        return Set(names)
    }

    private static func storedPausedMachines() -> [Machine] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.pausedMachines) else { return [] }
        return (try? JSONDecoder().decode([Machine].self, from: data)) ?? []
    }

    // MARK: Commands

    /// Makes a space with one terminal in a folder of this Mac or of a machine. No folder: the home folder.
    func newSpace(folder: String? = nil, machine: String? = nil) {
        Task {
            let (spaceID, tabID, paneID) = (qualified(LayoutDocument.newID("sp"), machine), qualified(LayoutDocument.newID("tb"), machine), qualified(LayoutDocument.newID("pd"), machine))
            guard let address = await runTerminal(machine: machine, folder: folder, spaceID: spaceID, tabID: tabID) else { return }
            layout.change(machine: machine) {
                $0.addSpace(id: spaceID, name: "", folder: folder ?? "", tabID: tabID, paneID: paneID, terminal: address)
            }
            activeSpaceID = spaceID
            activeTabIDs[spaceID] = tabID
        }
    }

    /// Asks for a folder and makes a space there.
    func newSpaceInFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "New Space"
        guard panel.runModal() == .OK, let folder = panel.url?.path else { return }
        newSpace(folder: folder)
    }

    /// Makes a tab with one terminal after the active tab.
    func newTab() {
        guard let space = activeSpace else { return newSpace() }
        Task {
            let machine = space.machine
            let (tabID, paneID) = (qualified(LayoutDocument.newID("tb"), machine), qualified(LayoutDocument.newID("pd"), machine))
            guard let address = await runTerminal(machine: machine, folder: folderForNewTerminal(in: space), spaceID: space.id, tabID: tabID) else { return }
            let previous = activeTab?.id
            layout.change(machine: machine) {
                $0.addTab(id: tabID, toSpace: space.id, after: previous, paneID: paneID, terminal: address)
            }
            activeTabIDs[space.id] = tabID
        }
    }

    /// Puts a new terminal beside the focused pane (`row`) or below it (`column`).
    func split(_ axis: LayoutDocument.Axis) {
        guard let space = activeSpace, let tab = activeTab, let target = focusedPaneID else { return }
        Task {
            let machine = space.machine
            let (paneID, containerID) = (qualified(LayoutDocument.newID("pd"), machine), qualified(LayoutDocument.newID("s"), machine))
            guard let address = await runTerminal(machine: machine, folder: folderForNewTerminal(in: space), spaceID: space.id, tabID: tab.id) else { return }
            layout.change(machine: machine) {
                $0.splitPane(target, axis: axis, newPaneID: paneID, containerID: containerID, terminal: address)
            }
            zoomedPaneIDs[tab.id] = nil
            focusedPaneIDs[tab.id] = paneID
        }
    }

    /// Stops the terminal of the focused pane and removes the pane.
    func closePane() {
        guard let space = activeSpace, let tab = activeTab, let paneID = focusedPaneID, let address = tab.root.address(ofPane: paneID) else { return }
        zoomedPaneIDs[tab.id] = nil
        layout.change(machine: space.machine) { $0.removePane(paneID) }
        stop([address])
    }

    /// Stops the terminals of the active tab and removes the tab. Returns false if there is no tab.
    @discardableResult
    func closeTab() -> Bool {
        guard let space = activeSpace, let tab = activeTab else { return false }
        close(tab, in: space)
        return true
    }

    func close(_ tab: LayoutDocument.Tab, in space: LayoutDocument.Space) {
        layout.change(machine: space.machine) { $0.removeTab(tab.id) }
        stop(tab.terminals)
    }

    func close(_ space: LayoutDocument.Space) {
        layout.change(machine: space.machine) { $0.removeSpace(space.id) }
        stop(space.tabs.flatMap(\.terminals))
    }

    func rename(_ space: LayoutDocument.Space, to name: String) {
        layout.change(machine: space.machine) { $0.renameSpace(space.id, to: name) }
    }

    func rename(_ tab: LayoutDocument.Tab, in space: LayoutDocument.Space, to name: String) {
        layout.change(machine: space.machine) { $0.renameTab(tab.id, to: name) }
    }

    func select(_ tab: LayoutDocument.Tab, in space: LayoutDocument.Space) {
        activeTabIDs[space.id] = tab.id
    }

    /// Selects a tab of the active space by its position. Positions start at 0.
    func selectTab(at index: Int) {
        guard let space = activeSpace, space.tabs.indices.contains(index) else { return }
        select(space.tabs[index], in: space)
    }

    func selectSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        activeSpaceID = spaces[index].id
    }

    /// Selects the tab after the active tab (`1`) or before it (`-1`). The last tab is before the first.
    func selectTab(offset: Int) {
        guard let space = activeSpace, let tab = activeTab, let index = space.tabs.firstIndex(of: tab) else { return }
        select(space.tabs[(index + offset + space.tabs.count) % space.tabs.count], in: space)
    }

    func selectSpace(offset: Int) {
        guard let space = activeSpace, let index = spaces.firstIndex(of: space) else { return }
        activeSpaceID = spaces[(index + offset + spaces.count) % spaces.count].id
    }

    /// Gives the keyboard to the pane after the focused pane (`1`) or before it (`-1`).
    func focusPane(offset: Int) {
        guard let tab = activeTab, let paneID = focusedPaneID else { return }
        let panes = tab.root.terminalPaneIDs
        guard let index = panes.firstIndex(of: paneID) else { return }
        focusedPaneIDs[tab.id] = panes[(index + offset + panes.count) % panes.count]
        focusActivePane()
    }

    /// Lets the focused pane fill the tab, or shows all panes again.
    func toggleZoom() {
        guard let tab = activeTab, let paneID = focusedPaneID else { return }
        zoomedPaneIDs[tab.id] = zoomedPaneIDs[tab.id] == nil ? paneID : nil
    }

    /// Shows the space and the tab that have a terminal, and gives the terminal the keyboard.
    func show(terminal address: String) {
        for space in spaces {
            for tab in space.tabs {
                guard let paneID = tab.root.terminalPaneIDs.first(where: { tab.root.address(ofPane: $0) == address }) else { continue }
                activeSpaceID = space.id
                activeTabIDs[space.id] = tab.id
                focusedPaneIDs[tab.id] = paneID
                zoomedPaneIDs[tab.id] = nil
                // The view of the terminal is in the window after SwiftUI drew the tab.
                Task { focusActivePane() }
                return
            }
        }
    }

    // MARK: Terminals in the core

    /// Starts a shell in a new terminal of a machine and returns its address.
    private func runTerminal(machine: String?, folder: String?, spaceID: String, tabID: String) async -> String? {
        guard let connection else { return nil }
        var parameters: JSONValue = [
            "env": ["TERM": "xterm-256color", "COLORTERM": "truecolor", "TERM_PROGRAM": "herdr"],
            // Herdr and Shep find the terminals of a tab by these labels. A terminal that a client starts was seen at turn 0.
            "labels": [
                "herdr.space": .string(LayoutDocument.localID(spaceID, machine: machine)),
                "herdr.tab": .string(LayoutDocument.localID(tabID, machine: machine)),
                "herdr.seen": "0",
            ],
            // A kept terminal gets a new shell if its program is lost, for example when the machine starts again.
            "keep": true,
            "no_parent": true,
        ]
        if let folder, !folder.isEmpty { parameters["cwd"] = .string(folder) }
        if let machine { parameters["on"] = .string(machine) }
        do {
            let result = try await connection.call("terminal.run", parameters)
            guard let address = result["address"].string else { return nil }
            return address.contains("/") ? address : qualified(address, machine)
        } catch {
            Self.logger.error("Start of a terminal failed: \(error)")
            presentError("Shep cannot start a terminal.", error)
            return nil
        }
    }

    private func stop(_ addresses: [String]) {
        for address in addresses {
            sessions.removeValue(forKey: address)?.detach()
            Task { _ = try? await connection?.call("terminal.kill", ["terminal": .string(address)]) }
        }
    }

    /// A terminal whose program ended goes out of the layout and out of the core.
    private func terminalDidFinish(_ address: String) {
        sessions.removeValue(forKey: address)?.detach()
        for space in spaces {
            for tab in space.tabs {
                guard let paneID = tab.root.terminalPaneIDs.first(where: { tab.root.address(ofPane: $0) == address }) else { continue }
                layout.change(machine: space.machine) { $0.removePane(paneID) }
            }
        }
        Task { _ = try? await connection?.call("terminal.rm", ["terminal": .string(address)]) }
    }

    private func folderForNewTerminal(in space: LayoutDocument.Space) -> String? {
        let focused = activeTab.flatMap { tab in focusedPaneID.flatMap { tab.root.address(ofPane: $0) } }.flatMap { terminals.terminals[$0] }
        if let folder = focused?.workingFolder, !folder.isEmpty { return folder }
        return space.folder.isEmpty ? nil : space.folder
    }

    private func qualified(_ id: String, _ machine: String?) -> String {
        machine.map { "\($0)/\(id)" } ?? id
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = (error as? CoreError)?.message ?? error.localizedDescription
        alert.runModal()
    }

    // MARK: Connection

    private func connect() async {
        guard let hc = HcBinary.find(configuredPath: UserDefaults.standard.string(forKey: SettingsKey.hcPath)) else {
            connectionState = .hcNotFound
            retryLater()
            return
        }
        do {
            let connection = try await CoreConnection.connect(hc: hc)
            // Subscribe before all other reads, so that no change is lost.
            let subscription = try await connection.call("events.subscribe")
            terminals.replace(snapshot: subscription)
            connection.onDisconnect = { [weak self] in self?.connectionDidClose() }
            self.connection = connection
            layout.connection = connection
            await layout.load(machine: nil)
            connectionState = .connected
            retryDelay = .seconds(1)
            if let channel = subscription["channel"].int {
                Task { await readEvents(from: connection, channel: UInt32(channel)) }
            }
            Task { await pollMachines(on: connection) }
            Task { await pollGitCounts(on: connection) }
        } catch {
            Self.logger.error("Connection to herdr-core failed: \(error)")
            connectionState = .failed(message: (error as? CoreError)?.message ?? error.localizedDescription)
            retryLater()
        }
    }

    private func connectionDidClose() {
        connection = nil
        layout.connection = nil
        // The streams of the old connection are closed: the sessions attach again on the new one.
        sessions.removeAll()
        connectionState = .connecting
        retryLater()
    }

    private func retryLater() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, .seconds(10))
        Task {
            try? await Task.sleep(for: delay)
            await connect()
        }
    }

    private func readEvents(from connection: CoreConnection, channel: UInt32) async {
        var lines = EventLineBuffer()
        for await case .data(let bytes) in connection.stream(channel) {
            for notification in lines.push(bytes) {
                switch notification["method"].string {
                case "event": handle(event: notification["params"])
                case "missed":
                    // Shep was too slow and the core left events out: all state is read again.
                    terminals.replace(snapshot: notification["params"])
                    await loadAllLayouts()
                default: break
                }
            }
            connection.credit(channel, bytes: bytes.count)
        }
    }

    private func handle(event: JSONValue) {
        let address = event["terminal"].string
        let oldStatus = address.flatMap { terminals.terminals[$0] }.flatMap(Attention.status(of:))
        terminals.apply(event: event)
        if let terminal = address.flatMap({ terminals.terminals[$0] }),
           let alert = Attention.alert(from: oldStatus, to: Attention.status(of: terminal)) {
            alerts.present(alert, for: terminal, isLooking: NSApp.isActive && visibleTerminals.contains(terminal.address))
        }
        switch event["type"].string {
        case "doc":
            if event["data"]["name"].string == LayoutDocument.name {
                Task { await layout.load(machine: event["machine"].string) }
            }
        case "restarted":
            // A kept terminal that lost its program has a new shell: its session attaches again.
            if let address { sessions[address]?.reattach() }
        case "finished":
            if let address { terminalDidFinish(address) }
        case "turn":
            // An agent stopped work. If it is on the screen, a person saw this turn.
            markVisibleAgentsSeen()
            // The agent possibly made a commit or a push.
            if let connection { Task { await readGitCounts(on: connection) } }
        default:
            break
        }
    }

    private func loadAllLayouts() async {
        await layout.load(machine: nil)
        for machine in machines where machine.state == .connected { await layout.load(machine: machine.name) }
    }

    /// Reads the list of machines again and again, while this connection is the current one.
    private func pollMachines(on connection: CoreConnection) async {
        while self.connection === connection {
            await readMachines(on: connection)
            try? await Task.sleep(for: Self.machinePollInterval)
        }
    }

    /// Reads the git counts again and again, while this connection is the current one and Shep is the active app.
    private func pollGitCounts(on connection: CoreConnection) async {
        while self.connection === connection {
            if NSApp.isActive || gitCounts.isEmpty { await readGitCounts(on: connection) }
            try? await Task.sleep(for: Self.gitPollInterval)
        }
    }

    private func readGitCounts(on connection: CoreConnection) async {
        var new: [String: GitCounts] = [:]
        for space in spaces {
            let folder = folder(of: space)
            guard !folder.isEmpty else { continue }
            func exec(_ command: [String]) async -> JSONValue? {
                var parameters: JSONValue = ["argv": .array(command.map { .string($0) }), "cwd": .string(folder), "timeout": 10]
                if let machine = space.machine { parameters["on"] = .string(machine) }
                return try? await connection.call("machine.exec", parameters)
            }
            // No answer, for example the machine is away: the space keeps what it showed.
            if let result = await exec(GitCounts.command) {
                new[space.id] = GitCounts(execResult: result)
            } else {
                new[space.id] = gitCounts[space.id]
            }
        }
        if new != gitCounts { gitCounts = new }
    }

    private func readMachines(on connection: CoreConnection) async {
        guard let result = try? await connection.call("machine.list") else { return }
        let new = Machine.list(from: result)
        let connected = { (machines: [Machine]) in Set(machines.filter { $0.state == .connected }.map(\.name)) }
        let newlyConnected = connected(new).subtracting(connected(machines))
        // A machine that came back to the core, for example added in Herdr, is not paused.
        // Only a new name counts: a list from before the pause can still have the paused machine.
        let added = Set(new.map(\.name)).subtracting(machines.map(\.name))
        if pausedMachines.contains(where: { added.contains($0.name) }) {
            pausedMachines.removeAll { added.contains($0.name) }
        }
        if new != machines { machines = new }
        layout.keepOnly(machines: connected(new))
        for name in newlyConnected { await layout.load(machine: name) }
    }
}

/// The keys in UserDefaults of what this window shows.
private enum ViewStateKey {
    static let activeSpace = "ActiveSpace"
    static let activeTabs = "ActiveTabs"
}
