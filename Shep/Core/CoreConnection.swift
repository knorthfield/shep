import Foundation
import os

/// An error that the core returned, or a failure of the connection.
struct CoreError: Error, Equatable {
    var message: String
    /// The core's stable error kind, for example `conflict` or `not_found`.
    var kind: String?
    var hint: String?

    static let disconnected = CoreError(message: "The connection to herdr-core closed.", kind: "disconnected")
    static let timedOut = CoreError(message: "herdr-core did not answer.", kind: "timeout")
}

/// What the core sends on a stream channel.
enum StreamEvent: Equatable, Sendable {
    case data(Data)
    case resize(columns: UInt16, rows: UInt16)
    /// The stream is over. The reason is `.null` when the core gave none.
    case close(reason: JSONValue)
}

/// A connection to herdr-core in framed mode, through the two ends of `hc connect`.
@MainActor
final class CoreConnection {
    struct Hello: Equatable {
        var version: String
        var features: Set<String>
        var coreName: String
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shep", category: "CoreConnection")
    static let callTimeout = Duration.seconds(10)

    let hello: Hello
    /// Called one time, when the connection closes.
    var onDisconnect: (() -> Void)?

    private let writer: FileHandle
    private var process: Process?
    private var nextCallID = 1
    private var pendingCalls: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var streams: [UInt32: (stream: AsyncStream<StreamEvent>, continuation: AsyncStream<StreamEvent>.Continuation)] = [:]
    private var isConnected = true

    /// Starts `hc connect` and does the handshake.
    static func connect(hc: URL) async throws -> CoreConnection {
        // If hc stops, a write must give an error, not stop Shep.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        let toCore = Pipe()
        let fromCore = Pipe()
        process.executableURL = hc
        process.arguments = ["connect"]
        process.standardInput = toCore
        process.standardOutput = fromCore
        process.standardError = FileHandle.nullDevice
        try process.run()
        let connection = try await CoreConnection(reading: fromCore.fileHandleForReading, writing: toCore.fileHandleForWriting)
        connection.process = process
        return connection
    }

    /// Does the handshake on the two ends of a connection to a core.
    init(reading: FileHandle, writing: FileHandle) async throws {
        writer = writing
        let incoming = Self.incoming(from: reading)
        try writing.write(contentsOf: Data(#"{"jsonrpc":"2.0","id":0,"method":"hello","params":{"framed":true}}"#.utf8) + Data([0x0A]))
        // The stream is read two times, one after the other: here for the first line, then for the frames.
        var first: Incoming?
        for await item in incoming {
            first = item
            break
        }
        guard case .helloLine(let line) = first, let reply = JSONValue(json: line) else {
            throw CoreError.disconnected
        }
        let result = try Self.result(of: reply)
        guard result["generation"].int == 1 else {
            throw CoreError(message: "This herdr-core uses a protocol that Shep does not know.", kind: "unsupported_generation")
        }
        hello = Hello(
            version: result["version"].string ?? "",
            features: Set((result["features"].array ?? []).compactMap(\.string)),
            coreName: result["core"]["name"].string ?? ""
        )
        Task { [weak self] in
            for await case .frame(let frame) in incoming {
                self?.handle(frame)
            }
            self?.disconnect()
        }
    }

    /// Calls a method of the core and returns its result.
    func call(_ method: String, _ params: JSONValue = [:], timeout: Duration = CoreConnection.callTimeout) async throws -> JSONValue {
        guard isConnected else { throw CoreError.disconnected }
        let id = nextCallID
        nextCallID += 1
        let request: JSONValue = ["jsonrpc": "2.0", "id": .int(Int64(id)), "method": .string(method), "params": params]
        send(.data, channel: 0, request.encoded())
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.pendingCalls.removeValue(forKey: id)?.resume(throwing: CoreError.timedOut)
        }
        return try await withCheckedThrowingContinuation { pendingCalls[id] = $0 }
    }

    /// The events of a stream channel that `terminal.attach` or `events.subscribe` returned.
    /// Events that came before this call are kept.
    func stream(_ channel: UInt32) -> AsyncStream<StreamEvent> {
        if let existing = streams[channel] { return existing.stream }
        let (stream, continuation) = AsyncStream.makeStream(of: StreamEvent.self)
        streams[channel] = (stream, continuation)
        return stream
    }

    func send(_ kind: FrameKind, channel: UInt32, _ payload: Data = Data()) {
        guard isConnected else { return }
        do {
            try writer.write(contentsOf: Frame(channel: channel, kind: kind, payload: payload).encoded())
        } catch {
            Self.logger.error("Write to herdr-core failed: \(error)")
            disconnect()
        }
    }

    /// Tells the core that Shep used this many bytes of a stream, so that the core sends more.
    func credit(_ channel: UInt32, bytes: Int) {
        var payload = Data()
        payload.appendLittleEndian(UInt32(bytes))
        send(.credit, channel: channel, payload)
    }

    /// Closes the connection. `hc connect` stops when its input closes; the core continues.
    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        try? writer.close()
        for continuation in pendingCalls.values { continuation.resume(throwing: CoreError.disconnected) }
        pendingCalls.removeAll()
        for stream in streams.values { stream.continuation.finish() }
        streams.removeAll()
        onDisconnect?()
    }

    private func handle(_ frame: Frame) {
        guard frame.channel != 0 else {
            if frame.kind == .data, let message = JSONValue(json: frame.payload) { handle(reply: message) }
            return
        }
        switch frame.kind {
        case .data:
            _ = stream(frame.channel)
            streams[frame.channel]?.continuation.yield(.data(frame.payload))
        case .resize where frame.payload.count == 4:
            _ = stream(frame.channel)
            let payload = frame.payload
            streams[frame.channel]?.continuation.yield(.resize(
                columns: payload.littleEndianUInt16(at: payload.startIndex),
                rows: payload.littleEndianUInt16(at: payload.startIndex + 2)
            ))
        case .close:
            // The closed stream stays, so that a reader that opens it later gets its last events.
            _ = stream(frame.channel)
            streams[frame.channel]?.continuation.yield(.close(reason: JSONValue(json: frame.payload) ?? .null))
            streams[frame.channel]?.continuation.finish()
        default:
            break
        }
    }

    private func handle(reply: JSONValue) {
        guard let id = reply["id"].int, let continuation = pendingCalls.removeValue(forKey: id) else { return }
        continuation.resume(with: Result { try Self.result(of: reply) })
    }

    private static func result(of reply: JSONValue) throws -> JSONValue {
        let error = reply["error"]
        guard error.isNull else {
            throw CoreError(
                message: error["message"].string ?? "herdr-core returned an error.",
                kind: error["data"]["kind"].string,
                hint: error["data"]["hint"].string
            )
        }
        return reply["result"]
    }

    private enum Incoming: Sendable {
        case helloLine(Data)
        case frame(Frame)
    }

    /// Reads the core's output on a background thread: first the one line that answers `hello`, then frames.
    private static func incoming(from reader: FileHandle) -> AsyncStream<Incoming> {
        let (stream, continuation) = AsyncStream.makeStream(of: Incoming.self)
        Thread.detachNewThread {
            var helloLine: Data? = Data()
            var decoder = FrameDecoder()
            while true {
                var bytes = reader.availableData
                if bytes.isEmpty { break }
                if var line = helloLine {
                    guard let newline = bytes.firstIndex(of: 0x0A) else {
                        helloLine = line + bytes
                        continue
                    }
                    line.append(bytes[..<newline])
                    continuation.yield(.helloLine(line))
                    helloLine = nil
                    bytes = bytes.suffix(from: newline + 1)
                }
                for frame in decoder.push(bytes) { continuation.yield(.frame(frame)) }
            }
            continuation.finish()
        }
        return stream
    }
}
