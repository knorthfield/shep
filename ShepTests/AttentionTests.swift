import Foundation
import Testing
@testable import Shep

struct AttentionTests {
    private func terminal(_ address: String = "t1", status: String? = "idle", turn: Int64 = 0, seen: String? = nil, pinned: String? = nil,
                          parent: String? = nil, created: Int64 = 0) -> TerminalRecord {
        var labels: [String: JSONValue] = [:]
        if let seen { labels["herdr.seen"] = .string(seen) }
        if let pinned { labels["herdr.pinned"] = .string(pinned) }
        var json: JSONValue = ["address": .string(address), "turn": .int(turn), "labels": .object(labels), "created_ms": .int(created)]
        if let status { json["status"] = ["state": .string(status), "app": "claude-code"] }
        if let parent { json["parent"] = .string(parent) }
        return TerminalRecord(json: json)
    }

    @Test func aTerminalWithoutAStatusIsNotAnAgent() {
        #expect(Attention.status(of: terminal(status: nil)) == nil)
    }

    @Test func blockedAndErrorNeedAPersonAndWorkingIsWorking() {
        #expect(Attention.status(of: terminal(status: "blocked")) == .blocked)
        #expect(Attention.status(of: terminal(status: "error")) == .blocked)
        #expect(Attention.status(of: terminal(status: "working", turn: 3, seen: "0")) == .working)
    }

    @Test func anAgentIsDoneUntilAPersonSawItsTurn() {
        #expect(Attention.status(of: terminal(status: "idle", turn: 2, seen: "1")) == .done)
        #expect(Attention.status(of: terminal(status: "done", turn: 2, seen: "2")) == .idle)
        #expect(Attention.status(of: terminal(status: "idle", turn: 0, seen: "0")) == .idle)
    }

    @Test func aMissingSeenLabelIsNotTurnZero() {
        #expect(Attention.status(of: terminal(status: "done", turn: 5, seen: nil)) == .idle)
    }

    @Test func theSeenLabelOnlyGoesUpAndAMissingLabelIsWritten() {
        #expect(Attention.seenValueToWrite(for: terminal(turn: 3, seen: "1")) == "3")
        #expect(Attention.seenValueToWrite(for: terminal(turn: 3, seen: "3")) == nil)
        #expect(Attention.seenValueToWrite(for: terminal(turn: 3, seen: "7")) == nil)
        #expect(Attention.seenValueToWrite(for: terminal(turn: 0, seen: nil)) == "0")
    }

    @Test func markUnreadWritesOneTurnBeforeTheCurrentTurn() {
        #expect(Attention.unreadValue(for: terminal(turn: 4)) == "3")
        #expect(Attention.unreadValue(for: terminal(turn: 0)) == nil)
    }

    @Test func aPinIsALabelThatIsNotEmpty() {
        #expect(Attention.isPinned(terminal(pinned: "1")))
        #expect(!Attention.isPinned(terminal(pinned: "")))
        #expect(!Attention.isPinned(terminal()))
    }

    @Test func theRollupIsTheMostImportantStatus() {
        #expect(Attention.rollup([.idle, .working, nil]) == .working)
        #expect(Attention.rollup([.working, .done]) == .done)
        #expect(Attention.rollup([.done, .blocked, .idle]) == .blocked)
        #expect(Attention.rollup([nil]) == nil)
    }

    @Test func anAlertComesWhenAnAgentStartsToNeedAPersonOrStopsWork() {
        #expect(Attention.alert(from: .working, to: .blocked) == .blocked)
        #expect(Attention.alert(from: .working, to: .done) == .done)
        #expect(Attention.alert(from: .blocked, to: .blocked) == nil)
        #expect(Attention.alert(from: .working, to: .idle) == nil)
        #expect(Attention.alert(from: .done, to: .working) == nil)
        #expect(Attention.alert(from: nil, to: .blocked) == .blocked)
    }

    @Test func pinnedAgentsAreFirstAndSubAgentsFollowTheirParent() {
        let ordered = Attention.ordered([
            terminal("t1", created: 1), terminal("t2", status: nil, created: 2), terminal("t3", pinned: "1", created: 3),
            terminal("t4", parent: "t1", created: 4), terminal("t5", parent: "t2", created: 5),
        ])
        #expect(ordered.map(\.terminal.address) == ["t3", "t1", "t4", "t5"])
        #expect(ordered.map(\.isSubAgent) == [false, false, true, false])
    }
}

struct ShepCommandTests {
    @Test func aShortcutIsShownWithTheSymbolsOfTheMenu() {
        let texts = Dictionary(uniqueKeysWithValues: ShepCommand.all.map { ($0.title, $0.shortcutText) })
        #expect(texts["New Tab"] == "⌘T")
        #expect(texts["Split Down"] == "⇧⌘D")
        #expect(texts["Zoom Pane"] == "⇧⌘↩")
        #expect(texts["Next Space"] == "⌥⌘]")
        #expect(texts["Space 3"] == "⌃3")
        #expect(texts["Close Tab"] == "")
    }

    @Test func eachCommandHasADifferentTitleAndShortcut() {
        #expect(Set(ShepCommand.all.map(\.title)).count == ShepCommand.all.count)
        let shortcuts = ShepCommand.all.map(\.shortcutText).filter { !$0.isEmpty }
        #expect(Set(shortcuts).count == shortcuts.count)
    }
}
