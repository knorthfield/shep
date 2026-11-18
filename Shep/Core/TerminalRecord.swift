import Foundation

/// The core's record of one terminal. The JSON is kept, and events change its fields.
struct TerminalRecord: Equatable, Identifiable {
    var json: JSONValue

    var id: String { address }
    /// For example `t7`, or `box/t7` for a terminal on a machine that this core added.
    var address: String { json["address"].string ?? "" }
    var name: String? { json["name"].string }
    var title: String { json["title"].string ?? "" }
    var workingFolder: String { json["foreground"]["cwd"].string ?? json["cwd"].string ?? "" }
    var isLive: Bool { json["state"].string == "live" }
    var createdMilliseconds: Int { json["created_ms"].int ?? 0 }
    var labels: [String: String] { (json["labels"].object ?? [:]).compactMapValues(\.string) }
    /// The address of the terminal that started this one.
    var parent: String? { json["parent"].string }
    /// The counter that goes up each time the program stops work.
    var turn: Int { json["turn"].int ?? 0 }
    /// The word that the program reported: `idle`, `working`, `done`, `blocked` or `error`.
    var statusWord: String? { json["status"]["state"].string }
    /// The agent that reports the status, for example `claude-code`.
    var statusApp: String? { json["status"]["app"].string }
    var foregroundName: String? { json["foreground"]["name"].string }

    /// The machine part of the address, or nil for a terminal on this core.
    var machine: String? {
        address.split(separator: "/", maxSplits: 1).count == 2 ? String(address.prefix { $0 != "/" }) : nil
    }

    /// The name to show: the name that the user gave, then the title that the program set, then the program.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if !title.isEmpty { return title }
        return foregroundName ?? json["argv"].array?.first?.string ?? address
    }
}
