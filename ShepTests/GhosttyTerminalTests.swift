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

    @Test func aColourThatAProgramNamesByNumberComesFromTheColoursOfTheTerminal() {
        terminal.setColors(TerminalColors(foreground: 0x010203, background: 0x040506, ansi: [0x000000, 0xAA0000] + Array(repeating: 0x111111, count: 14)))
        // Colour 1 is red. Colour 196 is not one of the 16 colours.
        terminal.write(Data("\u{1B}[31mR\u{1B}[38;5;196mX\u{1B}[0mN".utf8))
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].foreground == TerminalColor(hex: 0xAA0000))
        #expect(terminal.rows[0][1].foreground == TerminalColor(hex: 0xFF0000))
        #expect(terminal.rows[0][2].foreground == TerminalColor(hex: 0x010203))
        #expect(terminal.background == TerminalColor(hex: 0x040506))
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

    @Test(arguments: ["\u{07}", "\u{1B}\\"])
    func aProgramCanCopyTextToTheClipboard(terminator: String) {
        var copiedTexts: [String] = []
        terminal.onClipboardWrite = { copiedTexts.append($0) }
        // The attach stream can divide a sequence between two blocks of bytes.
        terminal.write(Data("\u{1B}]52;c;aGVs".utf8))
        #expect(copiedTexts.isEmpty)
        terminal.write(Data("bG8=\(terminator)".utf8))
        #expect(copiedTexts == ["hello"])
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

    @Test func commandLeftMovesToTheStartOfTheLine() {
        #expect(KeyMapping.commandKeyBytes(keyCode: 123, flags: [.command, .numericPad, .function]) == Data([0x01]))
    }

    @Test func commandRightMovesToTheEndOfTheLine() {
        #expect(KeyMapping.commandKeyBytes(keyCode: 124, flags: [.command, .numericPad, .function]) == Data([0x05]))
    }

    @Test func commandBackspaceDeletesToTheStartOfTheLine() {
        #expect(KeyMapping.commandKeyBytes(keyCode: 51, flags: [.command]) == Data([0x15]))
        #expect(KeyMapping.commandKeyBytes(keyCode: 51, flags: [.command, .shift]) == nil)
    }

    @Test func otherCommandKeysGoToTheMenu() {
        #expect(KeyMapping.commandKeyBytes(keyCode: 123, flags: [.command, .shift]) == nil)
        #expect(KeyMapping.commandKeyBytes(keyCode: 123, flags: [.command, .option]) == nil)
        #expect(KeyMapping.commandKeyBytes(keyCode: 0, flags: [.command]) == nil)
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

    @Test func clearHistoryRemovesTheRowsAboveTheScreen() {
        terminal.write(Data("\r\n3\r\n4\r\n5\r\n6".utf8))
        terminal.clearHistory()
        terminal.scroll(rows: -2)
        _ = terminal.refresh()
        #expect(terminal.rows[0][0].text == "3")
    }

    @Test func pastedTextGetsPasteMarksOnlyWhenTheProgramAskedForThem() {
        #expect(terminal.encodePaste("a\nb") == Data("a\rb".utf8))
        terminal.write(Data("\u{1B}[?2004h".utf8))
        #expect(terminal.encodePaste("a\nb") == Data("\u{1B}[200~a\nb\u{1B}[201~".utf8))
    }

    @Test func theWheelIsAMouseReportOnlyWhenTheProgramAskedForTheMouse() {
        #expect(!terminal.isMouseTracking)
        terminal.write(Data("\u{1B}[?1000h\u{1B}[?1006h".utf8))
        #expect(terminal.isMouseTracking)
        // The pointer is in the third column of the second row. Cells are 10 by 20.
        let up = terminal.encodeMouse(.press, button: .wheelUp, isButtonPressed: false, modifiers: [], x: 25, y: 30, cellWidth: 10, cellHeight: 20)
        #expect(String(decoding: up, as: UTF8.self) == "\u{1B}[<64;3;2M")
        let down = terminal.encodeMouse(.press, button: .wheelDown, isButtonPressed: false, modifiers: [], x: 25, y: 30, cellWidth: 10, cellHeight: 20)
        #expect(String(decoding: down, as: UTF8.self) == "\u{1B}[<65;3;2M")
        terminal.write(Data("\u{1B}[?1000l".utf8))
        #expect(!terminal.isMouseTracking)
    }

    @Test func aClickIsAMouseReportWithAPressAndARelease() {
        terminal.write(Data("\u{1B}[?1000h\u{1B}[?1006h".utf8))
        // The pointer is in the third column of the second row. Cells are 10 by 20.
        func report(_ action: GhosttyTerminal.MouseAction, _ button: GhosttyTerminal.MouseButton) -> String {
            let bytes = terminal.encodeMouse(action, button: button, isButtonPressed: action == .press, modifiers: [], x: 25, y: 30, cellWidth: 10, cellHeight: 20)
            return String(decoding: bytes, as: UTF8.self)
        }
        #expect(report(.press, .left) == "\u{1B}[<0;3;2M")
        #expect(report(.release, .left) == "\u{1B}[<0;3;2m")
        #expect(report(.press, .right) == "\u{1B}[<2;3;2M")
        #expect(report(.press, .middle) == "\u{1B}[<1;3;2M")
    }

    @Test func aDragIsAMouseReportOnlyWhenTheProgramAskedForDrags() {
        func drag(x: CGFloat) -> String {
            let bytes = terminal.encodeMouse(.motion, button: .left, isButtonPressed: true, modifiers: [], x: x, y: 30, cellWidth: 10, cellHeight: 20)
            return String(decoding: bytes, as: UTF8.self)
        }
        terminal.write(Data("\u{1B}[?1000h\u{1B}[?1006h".utf8))
        #expect(drag(x: 25) == "")
        terminal.write(Data("\u{1B}[?1002h".utf8))
        #expect(drag(x: 35) == "\u{1B}[<32;4;2M")
        #expect(drag(x: 45) == "\u{1B}[<32;5;2M")
    }

    @Test func theHistoryKeepsManyRows() {
        terminal.write(Data((1...1500).map { "line \($0)\r\n" }.joined().utf8))
        terminal.scroll(rows: -1400)
        _ = terminal.refresh()
        // The screen has 4 rows: the top row was line 1498.
        #expect(terminal.rows[0].prefix(8).map(\.text).joined() == "line 98")
    }

    @Test func theAlternateScreenIsKnown() {
        #expect(!terminal.isAlternateScreen)
        terminal.write(Data("\u{1B}[?1049h".utf8))
        #expect(terminal.isAlternateScreen)
    }
}
