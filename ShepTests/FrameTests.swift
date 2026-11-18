import Foundation
import Testing
@testable import Shep

struct FrameTests {
    private let frames = [
        Frame(channel: 0, kind: .data, payload: Data(#"{"id":1}"#.utf8)),
        Frame(channel: 7, kind: .resize, payload: Data([80, 0, 24, 0])),
        Frame(channel: 0x0102_0304, kind: .close),
    ]

    @Test func aFrameHasANineByteHeaderInLittleEndian() {
        let bytes = Frame(channel: 0x0102_0304, kind: .credit, payload: Data([9, 8])).encoded()
        #expect(Array(bytes) == [4, 3, 2, 1, 1, 2, 0, 0, 0, 9, 8])
    }

    @Test func manyFramesInOneChunkAreAllDecoded() {
        var decoder = FrameDecoder()
        let bytes = frames.reduce(Data()) { $0 + $1.encoded() }
        #expect(decoder.push(bytes) == frames)
    }

    @Test func framesAreDecodedWhenTheStreamBreaksAtEachByte() {
        var decoder = FrameDecoder()
        let bytes = frames.reduce(Data()) { $0 + $1.encoded() }
        let decoded = bytes.flatMap { decoder.push(Data([$0])) }
        #expect(decoded == frames)
    }

    @Test func aFrameOfAnUnknownKindIsIgnored() {
        var decoder = FrameDecoder()
        let unknown = Data([1, 0, 0, 0, 99, 1, 0, 0, 0, 5])
        #expect(decoder.push(unknown + frames[0].encoded()) == [frames[0]])
    }
}
