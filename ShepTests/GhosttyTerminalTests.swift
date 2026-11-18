import AppKit
import Testing
@testable import Shep

@MainActor
struct GhosttyTerminalTests {
    @Test func textWrittenToTheTerminalIsOnTheScreen() throws {
        let terminal = try #require(GhosttyTerminal(columns: 80, rows: 24))
        terminal.write(Data("hi\r\nthere".utf8))
        #expect(terminal.screenText() == "hi\nthere")
    }

    @Test func escapeSequencesMoveTheCursor() throws {
        let terminal = try #require(GhosttyTerminal(columns: 80, rows: 24))
        terminal.write(Data("abc\u{1B}[1;1HX".utf8))
        #expect(terminal.screenText() == "Xbc")
    }
}

@MainActor
struct TerminalScreenTests {
    private let terminal = GhosttyTerminal(columns: 10, rows: 3)!

    @Test func theFirstRefreshGivesAllRowsAndTheCursor() {
        terminal.write(Data("ab".utf8))
        #expect(terminal.refresh() == IndexSet(0..<3))
        #expect(terminal.rows.count == 3)
        #expect(terminal.rows[0].count == 10)
        #expect(terminal.rows[0].prefix(2).map(\.text) == ["a", "b"])
        #expect(terminal.cursor == TerminalCursor(column: 2, row: 0, shape: .block))
    }

    @Test func aRefreshAfterAChangeGivesOnlyTheRowsThatChanged() {
        _ = terminal.refresh()
        terminal.write(Data("\u{1B}[3;1Hx".utf8))
        // Row 2 has the new text. Row 0 had the cursor.
        #expect(terminal.refresh() == IndexSet([0, 2]))
    }

    @Test func coloursAndStylesOfACellAreRead() {
        terminal.write(Data("\u{1B}[1;3;4;38;2;10;20;30;48;2;1;2;3mX\u{1B}[0;7mY".utf8))
        _ = terminal.refresh()
        let styled = terminal.rows[0][0]
        #expect(styled.foreground == TerminalColor(red: 10, green: 20, blue: 30))
        #expect(styled.background == TerminalColor(red: 1, green: 2, blue: 3))
        #expect(styled.isBold && styled.isItalic && styled.isUnderlined)
        let inverse = terminal.rows[0][1]
        #expect(inverse.foreground == terminal.background)
        #expect(inverse.background == terminal.foreground)
    }

    @Test func aWideCharacterIsOneWideCell() {
        terminal.write(Data("日".utf8))
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].text == "日")
        #expect(terminal.rows[0][0].isWide)
        #expect(terminal.rows[0][1].text.isEmpty)
    }

    @Test func aResizeChangesTheGrid() {
        terminal.resize(columns: 20, rows: 5, cellWidth: 16, cellHeight: 34)
        _ = terminal.refresh()
        #expect(terminal.columns == 20)
        #expect(terminal.rows.count == 5)
    }

    @Test func theTerminalAnswersAQueryOfTheProgram() {
        terminal.write(Data("\u{1B}[6n".utf8))
        #expect(terminal.takeReplies() == Data("\u{1B}[1;1R".utf8))
        #expect(terminal.takeReplies().isEmpty)
    }

    @Test func keysAreEncodedForTheProgram() {
        let a = KeyMapping.key(forKeyCode: 0)
        #expect(terminal.encodeKey(a, modifiers: [], text: "a", unshiftedCodepoint: 97, isRepeat: false) == Data("a".utf8))
        #expect(terminal.encodeKey(a, modifiers: .shift, text: "A", unshiftedCodepoint: 97, isRepeat: false) == Data("A".utf8))
        let c = KeyMapping.key(forKeyCode: 8)
        #expect(terminal.encodeKey(c, modifiers: .control, text: "c", unshiftedCodepoint: 99, isRepeat: false) == Data([0x03]))
        #expect(terminal.encodeKey(a, modifiers: .option, text: "a", unshiftedCodepoint: 97, isRepeat: false) == Data("\u{1B}a".utf8))
        let up = KeyMapping.key(forKeyCode: 126)
        #expect(terminal.encodeKey(up, modifiers: [], text: "", unshiftedCodepoint: 0, isRepeat: false) == Data("\u{1B}[A".utf8))
        let enter = KeyMapping.key(forKeyCode: 36)
        #expect(terminal.encodeKey(enter, modifiers: [], text: "", unshiftedCodepoint: 0, isRepeat: false) == Data("\r".utf8))
    }

    @Test func arrowKeysFollowTheCursorKeyModeOfTheProgram() {
        terminal.write(Data("\u{1B}[?1h".utf8))
        let up = KeyMapping.key(forKeyCode: 126)
        #expect(terminal.encodeKey(up, modifiers: [], text: "", unshiftedCodepoint: 0, isRepeat: false) == Data("\u{1B}OA".utf8))
    }
}

struct KeyMappingTests {
    @Test func controlCharactersAndFunctionKeyCodesAreNotText() {
        #expect(KeyMapping.text("a") == "a")
        #expect(KeyMapping.text("\r") == "")
        #expect(KeyMapping.text("\u{7F}") == "")
        #expect(KeyMapping.text("\u{F700}") == "")
        #expect(KeyMapping.text(nil) == "")
    }

    @Test func modifierFlagsBecomeEncoderModifiers() {
        #expect(KeyMapping.modifiers([.shift, .control]) == [.shift, .control])
        #expect(KeyMapping.modifiers([.option, .command]) == [.option, .command])
    }
}

@MainActor
struct TerminalSelectionTests {
    private let terminal = GhosttyTerminal(columns: 20, rows: 4)!

    init() {
        terminal.write(Data("hello brave world\r\nsecond line".utf8))
        _ = terminal.refresh()
    }

    @Test func aDragSelectsTheCellsBetweenTwoPoints() {
        terminal.select(from: (column: 6, row: 0), to: (column: 10, row: 0))
        #expect(terminal.refresh().contains(0))
        #expect(terminal.rowSelections[0] == 6...10)
        #expect(terminal.rowSelections[1] == nil)
        #expect(terminal.selectedText() == "brave")
    }

    @Test func aSelectionAcrossRowsHasTheTextOfBothRows() {
        terminal.select(from: (column: 12, row: 0), to: (column: 5, row: 1))
        _ = terminal.refresh()
        #expect(terminal.selectedText() == "world\nsecond")
    }

    @Test func aDoubleClickSelectsAWordAndATripleClickSelectsALine() {
        terminal.selectWord(at: (column: 8, row: 0))
        #expect(terminal.selectedText() == "brave")
        terminal.selectLine(at: (column: 2, row: 1))
        #expect(terminal.selectedText() == "second line")
    }

    @Test func clearRemovesTheSelection() {
        terminal.selectAll()
        #expect(terminal.selectedText() == "hello brave world\nsecond line")
        terminal.clearSelection()
        _ = terminal.refresh()
        #expect(terminal.selectedText() == nil)
        #expect(terminal.rowSelections.allSatisfy { $0 == nil })
    }

    @Test func scrollShowsTheHistoryAndTheBottomShowsTheNewestRows() {
        terminal.write(Data("\r\n3\r\n4\r\n5\r\n6".utf8))
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].text == "3")
        terminal.scroll(rows: -2)
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].text == "h")
        terminal.scrollToBottom()
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].text == "3")
    }

    @Test func pastedTextGetsPasteMarksOnlyWhenTheProgramAskedForThem() {
        #expect(terminal.encodePaste("a\nb") == Data("a\rb".utf8))
        terminal.write(Data("\u{1B}[?2004h".utf8))
        #expect(terminal.encodePaste("a\nb") == Data("\u{1B}[200~a\nb\u{1B}[201~".utf8))
    }

    @Test func theAlternateScreenIsKnown() {
        #expect(!terminal.isAlternateScreen)
        terminal.write(Data("\u{1B}[?1049h".utf8))
        #expect(terminal.isAlternateScreen)
    }
}
