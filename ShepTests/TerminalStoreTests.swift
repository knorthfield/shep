import Foundation
import Testing
@testable import Shep

@MainActor
struct TerminalStoreTests {
    private let store = TerminalStore()

    init() {
        store.replace(snapshot: [
            "seq": 10,
            "terminals": [
                ["address": "t1", "state": "live", "title": "zsh", "created_ms": 1, "labels": ["herdr.space": "sp1"],
                 "pid": 42, "turn": 0, "foreground": ["name": "zsh", "cwd": "/tmp"]],
            ],
        ])
    }

    private func event(_ type: String, _ data: JSONValue, terminal: String = "t1", seq: Int64 = 11) -> JSONValue {
        ["seq": .int(seq), "type": .string(type), "terminal": .string(terminal), "data": data]
    }

    @Test func aSnapshotReplacesAllTerminals() {
        store.replace(snapshot: ["seq": 20, "terminals": [["address": "t5", "created_ms": 2], ["address": "t4", "created_ms": 1]]])
        #expect(store.ordered.map(\.address) == ["t4", "t5"])
    }

    @Test func anEventThatIsNotNewerThanTheSnapshotIsIgnored() {
        store.apply(event: event("title", ["title": "old"], seq: 10))
        #expect(store.terminals["t1"]?.title == "zsh")
    }

    @Test func createdAddsATerminalAndRemovedDropsIt() {
        store.apply(event: event("created", ["address": "box/t2", "state": "live"], terminal: "box/t2"))
        #expect(store.terminals["box/t2"]?.machine == "box")
        store.apply(event: event("removed", [:], terminal: "box/t2", seq: 12))
        #expect(store.terminals["box/t2"] == nil)
    }

    @Test func restartedReplacesTheRecord() {
        store.apply(event: event("restarted", ["address": "t1", "state": "live", "title": "new shell"]))
        #expect(store.terminals["t1"]?.title == "new shell")
        #expect(store.terminals["t1"]?.labels == [:])
    }

    @Test func statusAndTurnSetTheAgentState() {
        store.apply(event: event("status", ["status": ["state": "blocked", "app": "claude-code"], "records": [:], "reported": true]))
        store.apply(event: event("turn", ["turn": 3, "state": "done"], seq: 12))
        #expect(store.terminals["t1"]?.statusWord == "blocked")
        #expect(store.terminals["t1"]?.statusApp == "claude-code")
        #expect(store.terminals["t1"]?.turn == 3)
        store.apply(event: event("status", ["status": .null, "records": [:], "reported": true], seq: 13))
        #expect(store.terminals["t1"]?.statusWord == nil)
    }

    @Test func titleLabelsSizeKeepAndForegroundSetTheirFields() {
        store.apply(event: event("title", ["title": "vim"]))
        store.apply(event: event("labels", ["labels": ["herdr.pinned": "1"]], seq: 12))
        store.apply(event: event("size", ["cols": 100, "rows": 30], seq: 13))
        store.apply(event: event("keep", ["keep": true], seq: 14))
        store.apply(event: event("foreground", ["name": "vim", "cwd": "/src"], seq: 15))
        let terminal = store.terminals["t1"]
        #expect(terminal?.title == "vim")
        #expect(terminal?.labels == ["herdr.pinned": "1"])
        #expect(terminal?.json["cols"].int == 100)
        #expect(terminal?.json["keep"].bool == true)
        #expect(terminal?.workingFolder == "/src")
    }

    @Test func aLabelsEventWithARecordAddsTheTerminal() {
        store.apply(event: event("labels", ["labels": [:], "record": ["address": "t9", "state": "live"]], terminal: "t9"))
        #expect(store.terminals["t9"] != nil)
    }

    @Test func finishedSetsTheStateAndDropsTheForeground() {
        store.apply(event: event("finished", ["reason": "exited", "exit_code": 0, "signal": .null, "finished_ms": 99]))
        let terminal = store.terminals["t1"]
        #expect(terminal?.isLive == false)
        #expect(terminal?.json["exit_code"].int == 0)
        #expect(terminal?.foregroundName == nil)
    }

    @Test func aLostTerminalStaysLiveWithoutAProgram() {
        store.apply(event: event("lost", ["reason": "signaled", "exit_code": .null, "signal": 9, "finished_ms": .null]))
        let terminal = store.terminals["t1"]
        #expect(terminal?.isLive == true)
        #expect(terminal?.json["pid"].isNull == true)
        #expect(terminal?.json["reason"].string == "signaled")
    }

    @Test func aDocumentEventHasNoTerminalAndChangesNothing() {
        store.apply(event: ["seq": 11, "type": "doc", "data": ["name": "herdr-app", "version": 2]])
        #expect(store.terminals.count == 1)
    }
}

struct EventLineBufferTests {
    @Test func aLineThatBreaksAcrossFramesIsOneEvent() {
        var buffer = EventLineBuffer()
        #expect(buffer.push(Data(#"{"method":"ev"#.utf8)).isEmpty)
        let lines = buffer.push(Data(#"ent"}"#.utf8) + Data([0x0A]) + Data(#"{"method":"heartbeat"}"#.utf8) + Data([0x0A]) + Data("{".utf8))
        #expect(lines.map { $0["method"].string } == ["event", "heartbeat"])
    }
}
