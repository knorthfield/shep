import Foundation

/// The kinds of frame in herdr-core's framed mode.
enum FrameKind: UInt8, Sendable {
    case data = 0
    case credit = 1
    case close = 2
    case resize = 3
    case focus = 4
    case facts = 5
    case automaticInput = 6
}

/// One frame: `[channel u32 LE][kind u8][length u32 LE][payload]`.
/// Channel 0 carries JSON-RPC. Other channels are terminal and event streams.
struct Frame: Equatable, Sendable {
    static let headerLength = 9

    var channel: UInt32
    var kind: FrameKind
    var payload = Data()

    func encoded() -> Data {
        var bytes = Data(capacity: Self.headerLength + payload.count)
        bytes.appendLittleEndian(channel)
        bytes.append(kind.rawValue)
        bytes.appendLittleEndian(UInt32(payload.count))
        bytes.append(payload)
        return bytes
    }
}

/// Makes frames from a byte stream that can break at any byte.
struct FrameDecoder {
    private var buffer = Data()

    /// Adds bytes and returns the frames that are now complete.
    /// A frame of a kind that Shep does not know is ignored.
    mutating func push(_ bytes: Data) -> [Frame] {
        buffer.append(bytes)
        var frames: [Frame] = []
        while buffer.count >= Frame.headerLength {
            let start = buffer.startIndex
            let channel = buffer.littleEndianUInt32(at: start)
            let kind = FrameKind(rawValue: buffer[start + 4])
            let length = Int(buffer.littleEndianUInt32(at: start + 5))
            guard buffer.count >= Frame.headerLength + length else { break }
            let payload = buffer.subdata(in: (start + Frame.headerLength)..<(start + Frame.headerLength + length))
            buffer.removeFirst(Frame.headerLength + length)
            if let kind { frames.append(Frame(channel: channel, kind: kind, payload: payload)) }
        }
        return frames
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func littleEndianUInt32(at index: Index) -> UInt32 {
        UInt32(self[index]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24
    }

    func littleEndianUInt16(at index: Index) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }
}
