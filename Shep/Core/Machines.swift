import Foundation

/// A machine that the local core added: its terminals and its layout come through the local core.
struct Machine: Identifiable, Equatable {
    enum State: String {
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

    var id: String { name }

    /// The machines of a `machine.list` result. Machines that an agent added for a short time are not shown, as in Herdr.
    static func list(from result: JSONValue) -> [Machine] {
        (result["machines"].array ?? []).compactMap { machine in
            guard let name = machine["name"].string, machine["temporary"].bool != true else { return nil }
            return Machine(
                name: name,
                target: machine["target"].string ?? machine["host"].string ?? "",
                state: State(rawValue: machine["state"].string ?? "") ?? .connecting,
                reason: machine["why"].string ?? ""
            )
        }
    }
}
