import Foundation
import Observation

/// Divides the bytes of the event stream into lines. A line can break across frames.
struct EventLineBuffer {
    private var buffer = Data()

    /// Adds bytes and returns the lines that are now complete, as JSON.
    mutating func push(_ bytes: Data) -> [JSONValue] {
        buffer.append(bytes)
        var lines: [JSONValue] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            if let line = JSONValue(json: buffer[..<newline]) { lines.append(line) }
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

/// All the terminals of the core and its machines, kept current from the event stream.
@MainActor
@Observable
final class TerminalStore {
    private(set) var terminals: [String: TerminalRecord] = [:]
    @ObservationIgnored private var sequence = 0

    /// The terminals, oldest first.
    var ordered: [TerminalRecord] {
        terminals.values.sorted { ($0.createdMilliseconds, $0.address) < ($1.createdMilliseconds, $1.address) }
    }

    /// Replaces everything with a snapshot: the result of `events.subscribe` or the params of `missed`.
    func replace(snapshot: JSONValue) {
        sequence = snapshot["seq"].int ?? 0
        terminals = [:]
        for json in snapshot["terminals"].array ?? [] { add(json) }
    }

    /// Applies the params of one `event` notification. An event that is not newer than the snapshot is ignored.
    func apply(event: JSONValue) {
        guard let eventSequence = event["seq"].int, eventSequence > sequence else { return }
        sequence = eventSequence
        guard let address = event["terminal"].string else { return }
        let data = event["data"]
        switch event["type"].string {
        case "created", "restarted":
            add(data)
        case "removed":
            terminals[address] = nil
        case "labels":
            if data["record"].isNull { merge(["labels": data["labels"]], into: address) } else { add(data["record"]) }
        case "lost":
            merge(data, into: address)
            merge(["pid": .null, "foreground": .null], into: address)
        case "finished":
            merge(data, into: address)
            merge(["state": "finished", "foreground": .null], into: address)
        case "foreground":
            merge(["foreground": data], into: address)
        case "turn":
            merge(["turn": data["turn"]], into: address)
        case "status", "keep", "title", "size":
            merge(data, into: address)
        default:
            break
        }
    }

    private func add(_ json: JSONValue) {
        let record = TerminalRecord(json: json)
        guard !record.address.isEmpty else { return }
        terminals[record.address] = record
    }

    private func merge(_ fields: JSONValue, into address: String) {
        guard var record = terminals[address] else { return }
        for (key, value) in fields.object ?? [:] { record.json[key] = value }
        terminals[address] = record
    }
}
