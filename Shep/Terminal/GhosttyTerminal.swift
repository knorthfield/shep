import Foundation
import GhosttyVt

/// A colour of the terminal screen.
struct TerminalColor: Equatable, Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}

/// One cell of the terminal screen, ready to draw.
struct TerminalCell: Equatable {
    var text = ""
    var foreground: TerminalColor
    /// Nil: the background of the terminal.
    var background: TerminalColor?
    var isBold = false
    var isItalic = false
    var isFaint = false
    var isUnderlined = false
    var isStruckThrough = false
    /// A wide cell is two columns wide. The cell after it is empty.
    var isWide = false
}

/// The cursor on the terminal screen.
struct TerminalCursor: Equatable {
    enum Shape { case block, bar, underline }

    var column: Int
    var row: Int
    var shape: Shape
}

/// One libghostty-vt terminal: the screen state of one herdr-core terminal.
/// Only this file and `KeyMapping` use the libghostty-vt API.
@MainActor
final class GhosttyTerminal {
    private(set) var columns: Int
    private(set) var rowCount: Int
    /// The cells of the screen, by row. `refresh()` makes them current.
    private(set) var rows: [[TerminalCell]] = []
    /// The selected columns of each row. Nil: the row has no selected cell.
    private(set) var rowSelections: [ClosedRange<Int>?] = []
    private(set) var cursor: TerminalCursor?
    private(set) var foreground = TerminalColor(red: 0xD8, green: 0xD8, blue: 0xD8)
    private(set) var background = TerminalColor(red: 0x1C, green: 0x1C, blue: 0x1E)

    private let terminal: GhosttyVt.GhosttyTerminal
    private let renderState: GhosttyRenderState
    private let rowIterator: GhosttyRenderStateRowIterator
    private let rowCells: GhosttyRenderStateRowCells
    private let keyEncoder: GhosttyKeyEncoder
    private let keyEvent: GhosttyKeyEvent
    /// The answers of the terminal to queries of the program, for example a cursor position report.
    private var replies = Data()

    init?(columns: UInt16, rows: UInt16) {
        var terminal: GhosttyVt.GhosttyTerminal?
        var renderState: GhosttyRenderState?
        var rowIterator: GhosttyRenderStateRowIterator?
        var rowCells: GhosttyRenderStateRowCells?
        var keyEncoder: GhosttyKeyEncoder?
        var keyEvent: GhosttyKeyEvent?
        guard ghostty_terminal_new(nil, &terminal, columns, rows) == GHOSTTY_SUCCESS,
              ghostty_render_state_new(nil, &renderState) == GHOSTTY_SUCCESS,
              ghostty_render_state_row_iterator_new(nil, &rowIterator) == GHOSTTY_SUCCESS,
              ghostty_render_state_row_cells_new(nil, &rowCells) == GHOSTTY_SUCCESS,
              ghostty_key_encoder_new(nil, &keyEncoder) == GHOSTTY_SUCCESS,
              ghostty_key_event_new(nil, &keyEvent) == GHOSTTY_SUCCESS,
              let terminal, let renderState, let rowIterator, let rowCells, let keyEncoder, let keyEvent
        else {
            ghostty_key_event_free(keyEvent)
            ghostty_key_encoder_free(keyEncoder)
            ghostty_render_state_row_cells_free(rowCells)
            ghostty_render_state_row_iterator_free(rowIterator)
            ghostty_render_state_free(renderState)
            ghostty_terminal_free(terminal)
            return nil
        }
        self.terminal = terminal
        self.renderState = renderState
        self.rowIterator = rowIterator
        self.rowCells = rowCells
        self.keyEncoder = keyEncoder
        self.keyEvent = keyEvent
        self.columns = Int(columns)
        rowCount = Int(rows)

        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())
        let collectReply: GhosttyTerminalWritePtyFn = { _, userdata, bytes, count in
            guard let userdata, let bytes else { return }
            let owner = Unmanaged<GhosttyTerminal>.fromOpaque(userdata).takeUnretainedValue()
            // libghostty calls this during `write`, which is on the main actor.
            MainActor.assumeIsolated { owner.replies.append(bytes, count: count) }
        }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(collectReply, to: UnsafeRawPointer.self))
        setColors(foreground: foreground, background: background)
    }

    isolated deinit {
        ghostty_key_event_free(keyEvent)
        ghostty_key_encoder_free(keyEncoder)
        ghostty_render_state_row_cells_free(rowCells)
        ghostty_render_state_row_iterator_free(rowIterator)
        ghostty_render_state_free(renderState)
        ghostty_terminal_free(terminal)
    }

    /// Sets the colours that a cell without a colour of its own gets.
    func setColors(foreground: TerminalColor, background: TerminalColor) {
        var foregroundValue = GhosttyColorRgb(r: foreground.red, g: foreground.green, b: foreground.blue)
        var backgroundValue = GhosttyColorRgb(r: background.red, g: background.green, b: background.blue)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foregroundValue)
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &backgroundValue)
    }

    /// Gives program output (bytes from the attach stream) to the terminal.
    func write(_ bytes: Data) {
        bytes.withUnsafeBytes { buffer in
            ghostty_terminal_vt_write(terminal, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
    }

    /// Returns the answers to the program's queries since the last call, and removes them.
    func takeReplies() -> Data {
        defer { replies.removeAll() }
        return replies
    }

    func resize(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        guard columns > 0, rows > 0 else { return }
        ghostty_terminal_resize(terminal, UInt16(columns), UInt16(rows), UInt32(cellWidth), UInt32(cellHeight))
    }

    /// Makes `rows` and `cursor` current. Returns the rows that changed.
    func refresh() -> IndexSet {
        guard ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS else { return [] }
        var dirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        var columnCount: UInt16 = 0
        var newRowCount: UInt16 = 0
        var foregroundValue = GhosttyColorRgb()
        var backgroundValue = GhosttyColorRgb()
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirty)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &columnCount)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &newRowCount)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_FOREGROUND, &foregroundValue)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_BACKGROUND, &backgroundValue)
        foreground = TerminalColor(foregroundValue)
        background = TerminalColor(backgroundValue)
        columns = Int(columnCount)
        rowCount = Int(newRowCount)
        let all = dirty == GHOSTTY_RENDER_STATE_DIRTY_FULL || rows.count != rowCount
        if rows.count != rowCount {
            rows = Array(repeating: [], count: rowCount)
            rowSelections = Array(repeating: nil, count: rowCount)
        }

        var changed = IndexSet()
        var iterator: GhosttyRenderStateRowIterator? = rowIterator
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator)
        var row = 0
        while ghostty_render_state_row_iterator_next(rowIterator), row < rowCount {
            var isDirty = false
            ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &isDirty)
            if all || isDirty {
                rows[row] = readCellsOfCurrentRow()
                changed.insert(row)
            }
            let selection = readSelectionOfCurrentRow()
            if selection != rowSelections[row] {
                rowSelections[row] = selection
                changed.insert(row)
            }
            row += 1
        }
        ghostty_render_state_clean(renderState)

        let oldCursor = cursor
        cursor = readCursor()
        if oldCursor != cursor {
            for case let moved? in [oldCursor, cursor] where moved.row < rowCount { changed.insert(moved.row) }
        }
        return changed
    }

    /// The text on the screen, one line for each row, without the spaces at the end of lines.
    func screenText() -> String {
        var formatter: GhosttyFormatter?
        guard ghostty_formatter_terminal_new(nil, &formatter, terminal) == GHOSTTY_SUCCESS else { return "" }
        defer { ghostty_formatter_free(formatter) }
        var pointer: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard ghostty_formatter_format_alloc(formatter, nil, &pointer, &length) == GHOSTTY_SUCCESS, let pointer else { return "" }
        defer { ghostty_free(nil, pointer, length) }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
    }

    /// The bytes that a key press sends to the program, for the keyboard modes that the program set.
    /// - Parameters:
    ///   - text: The text that the key makes, without control characters. Empty for a key that makes no text.
    ///   - unshiftedCodepoint: The character of the key with no modifier keys, or 0.
    func encodeKey(_ key: GhosttyKey, modifiers: KeyModifiers, text: String, unshiftedCodepoint: UInt32, isRepeat: Bool) -> Data {
        ghostty_key_encoder_set_from_terminal(keyEncoder, terminal)
        var optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE
        ghostty_key_encoder_set(keyEncoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &optionAsAlt)
        ghostty_key_event_set_action(keyEvent, isRepeat ? GHOSTTY_KEY_ACTION_REPEAT : GHOSTTY_KEY_ACTION_PRESS)
        ghostty_key_event_set_key(keyEvent, key)
        ghostty_key_event_set_mods(keyEvent, modifiers.rawValue)
        // Shift is used up when it made the text, for example `A` from Shift-a.
        ghostty_key_event_set_consumed_mods(keyEvent, text.isEmpty ? 0 : modifiers.intersection(.shift).rawValue)
        ghostty_key_event_set_unshifted_codepoint(keyEvent, unshiftedCodepoint)
        var output = [UInt8](repeating: 0, count: 128)
        var written = 0
        // The key event does not copy the text: the bytes must stay until the key is encoded.
        Array(text.utf8).withUnsafeBufferPointer { utf8 in
            ghostty_key_event_set_utf8(keyEvent, GhosttyString(ptr: utf8.baseAddress, len: utf8.count))
            ghostty_key_encoder_encode(keyEncoder, keyEvent, &output, output.count, &written)
            ghostty_key_event_set_utf8(keyEvent, GhosttyString(ptr: nil, len: 0))
        }
        return Data(output.prefix(written))
    }

    // MARK: Selection

    /// Selects the cells from one cell to another cell. The cells are positions in the view.
    func select(from start: (column: Int, row: Int), to end: (column: Int, row: Int)) {
        var selection = GhosttySelection()
        guard gridReference(start, into: &selection.start), gridReference(end, into: &selection.end) else { return }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
    }

    func selectWord(at cell: (column: Int, row: Int)) {
        var options = GhosttyTerminalSelectWordOptions()
        ghostty_sized_init(&options, MemoryLayout<GhosttyTerminalSelectWordOptions>.size)
        var selection = GhosttySelection()
        guard gridReference(cell, into: &options.ref),
              ghostty_terminal_select_word(terminal, &options, &selection) == GHOSTTY_SUCCESS else { return }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
    }

    func selectLine(at cell: (column: Int, row: Int)) {
        var options = GhosttyTerminalSelectLineOptions()
        ghostty_sized_init(&options, MemoryLayout<GhosttyTerminalSelectLineOptions>.size)
        var selection = GhosttySelection()
        guard gridReference(cell, into: &options.ref),
              ghostty_terminal_select_line(terminal, &options, &selection) == GHOSTTY_SUCCESS else { return }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
    }

    func selectAll() {
        var selection = GhosttySelection()
        guard ghostty_terminal_select_all(terminal, &selection) == GHOSTTY_SUCCESS else { return }
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
    }

    func clearSelection() {
        ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SELECTION, nil)
    }

    /// The selected text, as the program wrote it: a line that the terminal wrapped is one line. Nil: nothing is selected.
    func selectedText() -> String? {
        var selection = GhosttySelection()
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS else { return nil }
        var formatter: GhosttyFormatter?
        guard ghostty_formatter_terminal_new(nil, &formatter, terminal) == GHOSTTY_SUCCESS else { return nil }
        defer { ghostty_formatter_free(formatter) }
        var unwrap = true
        ghostty_formatter_set(formatter, GHOSTTY_FORMATTER_OPT_UNWRAP, &unwrap)
        ghostty_formatter_set(formatter, GHOSTTY_FORMATTER_OPT_SELECTION, &selection)
        var pointer: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard ghostty_formatter_format_alloc(formatter, nil, &pointer, &length) == GHOSTTY_SUCCESS, let pointer else { return nil }
        defer { ghostty_free(nil, pointer, length) }
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
    }

    // MARK: Scrollback and paste

    /// Moves the view into the history. A negative number of rows goes up.
    func scroll(rows: Int) {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_TERMINAL_SCROLL_VIEWPORT_DELTA
        behavior.value.delta = rows
        ghostty_terminal_scroll_viewport(terminal, behavior)
    }

    func scrollToBottom() {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_TERMINAL_SCROLL_VIEWPORT_BOTTOM
        ghostty_terminal_scroll_viewport(terminal, behavior)
    }

    /// True when a full-screen program, for example an editor, has the screen. That screen has no history.
    var isAlternateScreen: Bool {
        var screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen)
        return screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
    }

    /// The bytes that send pasted text to the program: without control bytes, and in paste marks if the program asked for them.
    func encodePaste(_ text: String) -> Data {
        // Mode 2004 is bracketed paste. The mode value has the number in its low 15 bits.
        var mode = GhosttyTerminalModeConfig(mode: 2004, value: false)
        ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_MODE, &mode)
        var input = Array(text.utf8CString.dropLast())
        var needed = 0
        ghostty_paste_encode(&input, input.count, mode.value, nil, 0, &needed)
        var output = [UInt8](repeating: 0, count: needed)
        var written = 0
        guard ghostty_paste_encode(&input, input.count, mode.value, &output, output.count, &written) == GHOSTTY_SUCCESS else { return Data() }
        return Data(output.prefix(written))
    }

    private func gridReference(_ cell: (column: Int, row: Int), into reference: inout GhosttyGridRef) -> Bool {
        let column = UInt16(min(max(cell.column, 0), columns - 1))
        let row = UInt32(min(max(cell.row, 0), rowCount - 1))
        let point = GhosttyPoint(tag: GHOSTTY_POINT_TAG_VIEWPORT, value: GhosttyPointValue(coordinate: GhosttyPointCoordinate(x: column, y: row)))
        return ghostty_terminal_grid_ref(terminal, point, &reference) == GHOSTTY_SUCCESS
    }

    private func readSelectionOfCurrentRow() -> ClosedRange<Int>? {
        var selection = GhosttyRenderStateRowSelection()
        ghostty_sized_init(&selection, MemoryLayout<GhosttyRenderStateRowSelection>.size)
        guard ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS,
              selection.start_x <= selection.end_x else { return nil }
        return Int(selection.start_x)...Int(selection.end_x)
    }

    private func readCellsOfCurrentRow() -> [TerminalCell] {
        var cellsHandle: GhosttyRenderStateRowCells? = rowCells
        ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle)
        var cells: [TerminalCell] = []
        cells.reserveCapacity(columns)
        var utf8 = [UInt8](repeating: 0, count: 64)
        while ghostty_render_state_row_cells_next(rowCells) {
            var cell = TerminalCell(foreground: foreground)
            var foregroundValue = GhosttyColorRgb()
            if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &foregroundValue) == GHOSTTY_SUCCESS {
                cell.foreground = TerminalColor(foregroundValue)
            }
            var backgroundValue = GhosttyColorRgb()
            if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &backgroundValue) == GHOSTTY_SUCCESS {
                cell.background = TerminalColor(backgroundValue)
            }
            var hasStyling = false
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &hasStyling)
            if hasStyling {
                var style = GhosttyStyle()
                ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)
                let flags = StyleFlags(rawValue: style.flags)
                cell.isBold = flags.contains(.bold)
                cell.isItalic = flags.contains(.italic)
                cell.isFaint = flags.contains(.faint)
                cell.isStruckThrough = flags.contains(.strikethrough)
                cell.isUnderlined = style.flags & StyleFlags.underlineMask != 0
                if flags.contains(.inverse) {
                    let oldForeground = cell.foreground
                    cell.foreground = cell.background ?? background
                    cell.background = oldForeground
                }
                if flags.contains(.invisible) { cell.foreground = cell.background ?? background }
            }
            utf8.withUnsafeMutableBufferPointer { buffer in
                var text = GhosttyBuffer(ptr: buffer.baseAddress, cap: buffer.count, len: 0)
                if ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8, &text) == GHOSTTY_SUCCESS, text.len > 0 {
                    cell.text = String(decoding: UnsafeBufferPointer(start: buffer.baseAddress, count: text.len), as: UTF8.self)
                }
            }
            var raw: GhosttyCell = 0
            var wide = GHOSTTY_CELL_WIDE_NARROW
            ghostty_render_state_row_cells_get(rowCells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw)
            ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide)
            cell.isWide = wide == GHOSTTY_CELL_WIDE_WIDE
            cells.append(cell)
        }
        return cells
    }

    private func readCursor() -> TerminalCursor? {
        var isVisible = false
        var isInViewport = false
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &isVisible)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &isInViewport)
        guard isVisible, isInViewport else { return nil }
        var column: UInt16 = 0
        var row: UInt16 = 0
        var style = GHOSTTY_CURSOR_STYLE_BLOCK
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &column)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &row)
        ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &style)
        let shape: TerminalCursor.Shape = switch style {
        case GHOSTTY_CURSOR_STYLE_BAR: .bar
        case GHOSTTY_CURSOR_STYLE_UNDERLINE: .underline
        default: .block
        }
        return TerminalCursor(column: Int(column), row: Int(row), shape: shape)
    }
}

/// The modifier keys of a key press, with the bit values of libghostty-vt (`GHOSTTY_MODS_*`).
struct KeyModifiers: OptionSet {
    let rawValue: UInt16

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// The style bits of a cell, with the bit values of libghostty-vt (`GHOSTTY_STYLE_FLAG_*`).
private struct StyleFlags: OptionSet {
    let rawValue: UInt16

    static let bold = StyleFlags(rawValue: 1 << 0)
    static let italic = StyleFlags(rawValue: 1 << 1)
    static let faint = StyleFlags(rawValue: 1 << 2)
    static let inverse = StyleFlags(rawValue: 1 << 4)
    static let invisible = StyleFlags(rawValue: 1 << 5)
    static let strikethrough = StyleFlags(rawValue: 1 << 6)
    static let underlineMask: UInt16 = 0x7 << 8
}

private extension TerminalColor {
    init(_ color: GhosttyColorRgb) {
        self.init(red: color.r, green: color.g, blue: color.b)
    }
}
