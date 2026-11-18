import Foundation
import Testing
@testable import Shep

@MainActor
struct LayoutStoreTests {
    private let core = FakeCore()
    private let store = LayoutStore()

    /// Reads the next request of Shep and answers it.
    private func answer(_ reply: String) async throws -> JSONValue {
        let request = try #require(JSONValue(json: await core.nextFrame().payload))
        core.send(json: #"{"jsonrpc":"2.0","id":\#(request["id"].int!),\#(reply)}"#)
        return request
    }

    private func loadOneSpace(version: Int = 43) async throws {
        store.connection = try await core.connect()
        let load = Task { await store.load(machine: nil) }
        let request = try await answer(#""result":{"value":{"spaces":[{"id":"sp1","name":"web","tabs":[]}]},"version":\#(version)}"#)
        #expect(request["method"] == "doc.get")
        #expect(request["params"] == ["name": "herdr-app"])
        await load.value
    }

    @Test func loadReadsTheDocumentOfTheLocalCore() async throws {
        try await loadOneSpace()
        #expect(store.spaces.map(\.name) == ["web"])
    }

    @Test func loadOfAMachineAsksThatMachineAndQualifiesTheIds() async throws {
        store.connection = try await core.connect()
        let load = Task { await store.load(machine: "box") }
        let request = try await answer(#""result":{"value":{"spaces":[{"id":"sp1","tabs":[]}]},"version":1}"#)
        #expect(request["params"] == ["name": "herdr-app", "on": "box"])
        await load.value
        #expect(store.spaces.map(\.id) == ["box/sp1"])
    }

    @Test func aChangeIsShownImmediatelyAndWrittenWithTheVersionThatWasRead() async throws {
        try await loadOneSpace()
        store.change(machine: nil) { $0.renameSpace("sp1", to: "api") }
        #expect(store.spaces.map(\.name) == ["api"])
        let request = try await answer(#""result":{"version":44}"#)
        #expect(request["method"] == "doc.set")
        #expect(request["params"]["version"] == 43)
        #expect(request["params"]["value"]["spaces"].array?[0]["name"] == "api")

        // The next write uses the version that the core returned.
        try await Task.sleep(for: .milliseconds(50))
        store.change(machine: nil) { $0.renameSpace("sp1", to: "docs") }
        let second = try await answer(#""result":{"version":45}"#)
        #expect(second["params"]["version"] == 44)
    }

    @Test func aChangeThatChangesNothingIsNotWritten() async throws {
        try await loadOneSpace()
        store.change(machine: nil) { $0.renameSpace("absent", to: "x") }
        store.change(machine: nil) { $0.renameSpace("sp1", to: "api") }
        let request = try await answer(#""result":{"version":44}"#)
        #expect(request["params"]["value"]["spaces"].array?[0]["name"] == "api")
    }

    @Test func aConflictReadsTheDocumentAgainAndTheOtherClientWins() async throws {
        try await loadOneSpace()
        store.change(machine: nil) { $0.renameSpace("sp1", to: "mine") }
        _ = try await answer(#""error":{"code":-32000,"message":"stale","data":{"kind":"conflict"}}"#)
        let reload = try await answer(#""result":{"value":{"spaces":[{"id":"sp1","name":"theirs","tabs":[]}]},"version":50}"#)
        #expect(reload["method"] == "doc.get")
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.spaces.map(\.name) == ["theirs"])
    }
}
