import Foundation

/// What an agent shows, from the least important to the most important.
enum AgentStatus: Int, Comparable {
    case idle
    case working
    /// The agent stopped work and no person looked at it since.
    case done
    /// The agent needs a person: it is blocked or it has an error.
    case blocked

    static func < (left: AgentStatus, right: AgentStatus) -> Bool { left.rawValue < right.rawValue }
}

/// The rules that Herdr's clients share for the labels `herdr.seen` and `herdr.pinned` (Herdr's `docs/labels.md`).
enum Attention {
    static let seenLabel = "herdr.seen"
    static let pinnedLabel = "herdr.pinned"

    enum Alert: Equatable {
        case blocked
        case done
    }

    /// The status to show for a terminal. Nil: the program in the terminal does not report a status, so it is not an agent.
    static func status(of terminal: TerminalRecord) -> AgentStatus? {
        guard let word = terminal.statusWord else { return nil }
        switch word {
        case "blocked", "error": return .blocked
        case "working": return .working
        default:
            // Without the label, a terminal that another client started counts as seen.
            guard let seen = terminal.labels[seenLabel].flatMap({ Int($0) }) else { return .idle }
            return terminal.turn > seen ? .done : .idle
        }
    }

    /// The most important status of a group of terminals, for example of a space.
    static func rollup(_ statuses: [AgentStatus?]) -> AgentStatus? {
        statuses.compactMap { $0 }.max()
    }

    /// The value to write to `herdr.seen` when a person looks at the terminal. Nil: no write.
    /// The label only goes up, and a terminal without the label gets one.
    static func seenValueToWrite(for terminal: TerminalRecord) -> String? {
        if let seen = terminal.labels[seenLabel].flatMap({ Int($0) }), seen >= terminal.turn { return nil }
        return String(terminal.turn)
    }

    /// The value that marks the terminal as not read: one turn before the current turn. Nil: nothing has finished yet.
    static func unreadValue(for terminal: TerminalRecord) -> String? {
        terminal.turn > 0 ? String(terminal.turn - 1) : nil
    }

    static func isPinned(_ terminal: TerminalRecord) -> Bool {
        !(terminal.labels[pinnedLabel] ?? "").isEmpty
    }

    /// The alert for a change of status: when an agent starts to need a person, or when it stops work.
    static func alert(from old: AgentStatus?, to new: AgentStatus?) -> Alert? {
        guard old != new else { return nil }
        switch new {
        case .blocked: return .blocked
        case .done: return .done
        default: return nil
        }
    }

    /// The agents of the sidebar in groups by status, the most important status first. A sub-agent is in the group of its parent.
    static func grouped(_ terminals: [TerminalRecord]) -> [(status: AgentStatus, agents: [(terminal: TerminalRecord, isSubAgent: Bool)])] {
        var groups: [AgentStatus: [(terminal: TerminalRecord, isSubAgent: Bool)]] = [:]
        var statusOfParent = AgentStatus.idle
        for agent in ordered(terminals) {
            if !agent.isSubAgent { statusOfParent = status(of: agent.terminal) ?? .idle }
            groups[statusOfParent, default: []].append(agent)
        }
        return groups.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    /// The time since a date in a few characters, for example `5m`, `2h` or `3d`.
    static func age(since date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 60 * 24 { return "\(minutes / 60)h" }
        return "\(minutes / (60 * 24))d"
    }

    /// The agents in the order of the sidebar: pinned agents first, then by age. A sub-agent comes after its parent.
    static func ordered(_ terminals: [TerminalRecord]) -> [(terminal: TerminalRecord, isSubAgent: Bool)] {
        // A terminal that reported a status earlier, and has none now, is a shell where an agent stopped.
        let agents = terminals.filter { $0.statusWord != nil }
        let addresses = Set(agents.map(\.address))
        let roots = agents.filter { $0.parent.map { !addresses.contains($0) } ?? true }
        let sortedRoots = roots.filter(isPinned) + roots.filter { !isPinned($0) }
        return sortedRoots.flatMap { root in
            [(root, false)] + agents.filter { $0.parent == root.address }.map { ($0, true) }
        }
    }
}
