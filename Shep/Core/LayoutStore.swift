import Foundation
import Observation
import os

/// The layout documents of the local core and of its machines, kept the same as the documents in the cores.
///
/// A change is shown immediately and then written with the version that Shep read. If another client
/// wrote first, the core refuses the write: Shep then reads the document again and its own change is lost, as in Herdr.
@MainActor
@Observable
final class LayoutStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shep", category: "LayoutStore")
    /// The key of the local core's document. The other keys are machine names.
    private static let localKey = ""

    private(set) var documents: [String: LayoutDocument] = [:]
    @ObservationIgnored var connection: CoreConnection?
    @ObservationIgnored private var versions: [String: Int] = [:]
    @ObservationIgnored private var keysInWrite: Set<String> = []
    @ObservationIgnored private var keysToWriteAgain: Set<String> = []

    /// All spaces: those of the local core first, then those of each machine.
    var spaces: [LayoutDocument.Space] {
        documents.keys.sorted().flatMap { documents[$0]?.spaces ?? [] }
    }

    /// Forgets the documents, for example of machines that are gone. The local document stays.
    func keepOnly(machines: Set<String>) {
        for key in documents.keys where key != Self.localKey && !machines.contains(key) {
            documents[key] = nil
            versions[key] = nil
        }
    }

    /// Reads the document of a machine from its core. Nil: the local core.
    func load(machine: String?) async {
        let key = machine ?? Self.localKey
        // A write is in work: its result decides. If it fails with a conflict, it reads again.
        guard let connection, !keysInWrite.contains(key) else { return }
        do {
            let result = try await connection.call("doc.get", Self.parameters(machine: machine, ["name": .string(LayoutDocument.name)]))
            guard !keysInWrite.contains(key) else { return }
            documents[key] = LayoutDocument(value: result["value"], machine: machine)
            versions[key] = result["version"].int ?? 0
        } catch {
            Self.logger.error("Read of the layout of \(key) failed: \(error)")
        }
    }

    /// Changes the document of a machine and writes it to its core.
    func change(machine: String?, _ edit: (inout LayoutDocument) -> Void) {
        let key = machine ?? Self.localKey
        var document = documents[key] ?? LayoutDocument(value: .null, machine: machine)
        edit(&document)
        guard document != documents[key] else { return }
        documents[key] = document
        Task { await write(machine: machine) }
    }

    private func write(machine: String?) async {
        let key = machine ?? Self.localKey
        guard !keysInWrite.contains(key) else {
            keysToWriteAgain.insert(key)
            return
        }
        keysInWrite.insert(key)
        defer { keysInWrite.remove(key) }
        repeat {
            keysToWriteAgain.remove(key)
            guard let connection, let document = documents[key] else { return }
            do {
                let result = try await connection.call("doc.set", Self.parameters(machine: machine, [
                    "name": .string(LayoutDocument.name),
                    "value": document.value,
                    "version": .int(Int64(versions[key] ?? 0)),
                ]))
                versions[key] = result["version"].int ?? versions[key]
            } catch let error as CoreError where error.kind == "conflict" {
                // Another client wrote first. Its document wins.
                keysInWrite.remove(key)
                keysToWriteAgain.remove(key)
                await load(machine: machine)
                return
            } catch {
                Self.logger.error("Write of the layout of \(key) failed: \(error)")
                return
            }
        } while keysToWriteAgain.contains(key)
    }

    private static func parameters(machine: String?, _ parameters: JSONValue) -> JSONValue {
        var parameters = parameters
        if let machine { parameters["on"] = .string(machine) }
        return parameters
    }
}
