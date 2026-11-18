import Foundation
import Testing
@testable import Shep

/// The core's end of a connection, for tests.
struct FakeCore {
    private let fromShep = Pipe()
    private let toShep = Pipe()

    var shepReads: FileHandle { toShep.fileHandleForReading }
    var shepWrites: FileHandle { fromShep.fileHandleForWriting }

    /// Answers the `hello` that Shep sends first.
    func answerHello(generation: Int = 1) {
        let reply = #"{"jsonrpc":"2.0","id":0,"result":{"generation":\#(generation),"version":"0.1.17","methods":[],"features":["framed","automatic_input"],"core":{"id":"c1","name":"box"}}}"#
        toShep.fileHandleForWriting.write(Data(reply.utf8) + Data([0x0A]))
    }

    /// The next frame that Shep sent. The read is off the main actor, so that Shep can send during the wait.
    func nextFrame() async -> Frame {
        let reader = fromShep.fileHandleForReading
        return await Task.detached {
            let header = reader.readData(ofLength: Frame.headerLength)
            let length = Int(header.littleEndianUInt32(at: header.startIndex + 5))
            var decoder = FrameDecoder()
            return decoder.push(header + reader.readData(ofLength: length))[0]
        }.value
    }

    func send(_ frame: Frame) {
        toShep.fileHandleForWriting.write(frame.encoded())
    }

    func send(json: String, channel: UInt32 = 0) {
        send(Frame(channel: channel, kind: .data, payload: Data(json.utf8)))
    }

    func close() {
        try? toShep.fileHandleForWriting.close()
    }

    @MainActor func connect() async throws -> CoreConnection {
        answerHello()
        let connection = try await CoreConnection(reading: shepReads, writing: shepWrites)
        // Remove Shep's `hello` line, so that the frames come next.
        _ = fromShep.fileHandleForReading.availableData
        return connection
    }
}

@MainActor
struct CoreConnectionTests {
    @Test func theHandshakeReadsTheCoreVersionAndFeatures() async throws {
        let connection = try await FakeCore().connect()
        #expect(connection.hello == CoreConnection.Hello(version: "0.1.17", features: ["framed", "automatic_input"], coreName: "box"))
    }

    @Test func aCoreOfADifferentGenerationIsRefused() async {
        let core = FakeCore()
        core.answerHello(generation: 2)
        await #expect(throws: CoreError.self) {
            _ = try await CoreConnection(reading: core.shepReads, writing: core.shepWrites)
        }
    }

    @Test func aCallSendsARequestAndReturnsTheResult() async throws {
        let core = FakeCore()
        let connection = try await core.connect()
        let result = Task { try await connection.call("terminal.get", ["terminal": "t1"]) }
        let request = try #require(JSONValue(json: await core.nextFrame().payload))
        #expect(request["method"].string == "terminal.get")
        #expect(request["params"]["terminal"].string == "t1")
        core.send(json: #"{"jsonrpc":"2.0","id":\#(request["id"].int!),"result":{"address":"t1"}}"#)
        #expect(try await result.value["address"].string == "t1")
    }

    @Test func anErrorReplyThrowsTheKindAndTheHint() async throws {
        let core = FakeCore()
        let connection = try await core.connect()
        let result = Task { try await connection.call("doc.set") }
        let id = try #require(JSONValue(json: await core.nextFrame().payload))["id"].int!
        core.send(json: #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32000,"message":"stale","data":{"kind":"conflict","hint":"read again"}}}"#)
        await #expect(throws: CoreError(message: "stale", kind: "conflict", hint: "read again")) {
            _ = try await result.value
        }
    }

    @Test func aStreamGivesTheFramesThatCameBeforeItWasOpened() async throws {
        let core = FakeCore()
        let connection = try await core.connect()
        core.send(Frame(channel: 5, kind: .data, payload: Data("out".utf8)))
        core.send(Frame(channel: 5, kind: .resize, payload: Data([80, 0, 24, 0])))
        core.send(Frame(channel: 5, kind: .close, payload: Data(#"{"reason":"exited"}"#.utf8)))
        // A call goes through the same loop, so the frames above are handled when it returns.
        let result = Task { try await connection.call("server.status") }
        let id = try #require(JSONValue(json: await core.nextFrame().payload))["id"].int!
        core.send(json: #"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)
        _ = try await result.value

        var events: [StreamEvent] = []
        for await event in connection.stream(5) { events.append(event) }
        #expect(events == [.data(Data("out".utf8)), .resize(columns: 80, rows: 24), .close(reason: ["reason": "exited"])])
    }

    @Test func creditIsSentAsALittleEndianByteCount() async throws {
        let core = FakeCore()
        let connection = try await core.connect()
        connection.credit(5, bytes: 258)
        #expect(await core.nextFrame() == Frame(channel: 5, kind: .credit, payload: Data([2, 1, 0, 0])))
    }

    @Test func aCallFailsWhenTheCoreCloses() async throws {
        let core = FakeCore()
        let connection = try await core.connect()
        var disconnects = 0
        connection.onDisconnect = { disconnects += 1 }
        let result = Task { try await connection.call("terminal.list") }
        _ = await core.nextFrame()
        core.close()
        await #expect(throws: CoreError.disconnected) { _ = try await result.value }
        #expect(disconnects == 1)
        await #expect(throws: CoreError.disconnected) { _ = try await connection.call("terminal.list") }
    }
}

struct HcBinaryTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    @Test func thePathFromSettingsComesFirst() {
        let found = HcBinary.find(configuredPath: "/custom/hc", environmentPath: "/bin", home: home) { _ in true }
        #expect(found?.path == "/custom/hc")
    }

    @Test func theFoldersOfThePathComeBeforeTheUsualFolders() {
        let found = HcBinary.find(configuredPath: nil, environmentPath: "/usr/bin:/tools", home: home) {
            ["/tools/hc", "/opt/homebrew/bin/hc"].contains($0)
        }
        #expect(found?.path == "/tools/hc")
    }

    @Test func theInstallFolderInTheHomeFolderIsFoundWithAShortPath() {
        let found = HcBinary.find(configuredPath: "", environmentPath: "/usr/bin", home: home) { $0 == "/Users/someone/.local/bin/hc" }
        #expect(found?.path == "/Users/someone/.local/bin/hc")
    }

    @Test func nothingIsFoundWhenHcIsNotInstalled() {
        #expect(HcBinary.find(configuredPath: nil, environmentPath: "/usr/bin", home: home) { _ in false } == nil)
    }
}
