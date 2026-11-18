import Foundation

/// A machine that the local core added: its terminals and its layout come through the local core.
struct Machine: Identifiable, Equatable, Codable {
    enum State: String, Codable {
        case connecting
        case connected
        /// SSH needs the user, for example for a password.
        case needsLogin = "needs_login"
        case unreachable
    }

    var name: String
    /// The SSH target, for example `user@host`.
    var target: String
    var state: State
    /// The reason for the state, in the core's words.
    var reason: String
    /// The hc session on the machine, or nil for its default session.
    var session: String? = nil
    /// True if `target` is a command that takes the place of `ssh`.
    var isCommand = false

    var id: String { name }

    /// The machines of a `machine.list` result. Machines that an agent added for a short time are not shown, as in Herdr.
    static func list(from result: JSONValue) -> [Machine] {
        (result["machines"].array ?? []).compactMap { machine in
            guard let name = machine["name"].string, machine["temporary"].bool != true else { return nil }
            return Machine(
                name: name,
                target: machine["target"].string ?? machine["host"].string ?? "",
                state: State(rawValue: machine["state"].string ?? "") ?? .connecting,
                reason: machine["why"].string ?? "",
                session: machine["session"].string,
                isCommand: machine["via"].bool ?? false
            )
        }
    }

    /// The parameters of `machine.add` that add this machine again with the same name.
    var addParameters: JSONValue {
        var parameters: JSONValue = ["name": .string(name), isCommand ? "via" : "target": .string(target)]
        if let session { parameters["session"] = .string(session) }
        return parameters
    }
}
