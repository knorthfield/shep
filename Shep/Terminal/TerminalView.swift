import AppKit
import CoreText

/// Draws one terminal with CoreText and sends key presses to it.
@MainActor
final class TerminalView: NSView {
    /// The space between the edge of the view and the cells.
    static let padding: CGFloat = 6
    /// The view is flipped: this text matrix turns the text the right way up.
    private static let uprightText = CGAffineTransform(scaleX: 1, y: -1)
    private static let darkColors = (foreground: TerminalColor(red: 0xD8, green: 0xD8, blue: 0xD8), background: TerminalColor(red: 0x1C, green: 0x1C, blue: 0x1E))
    private static let lightColors = (foreground: TerminalColor(red: 0x1D, green: 0x1D, blue: 0x1F), background: TerminalColor(red: 0xFF, green: 0xFF, blue: 0xFF))

    /// Bytes that the user typed or pasted, to send to the program.
    var onInput: ((Data) -> Void)?
    /// The view has a new number of columns and rows.
    var onGridChange: ((_ columns: Int, _ rows: Int) -> Void)?
    /// The view got or lost the keyboard.
    var onFocusChange: ((Bool) -> Void)?
    /// The colours of the terminal changed with the appearance of macOS.
    var onColorChange: (() -> Void)?

    private let terminal: GhosttyTerminal
    private let font: CTFont
    private let boldFont: CTFont
    private let italicFont: CTFont
    private let boldItalicFont: CTFont
    let cellSize: CGSize
    private let baseline: CGFloat
    private var glyphs: [GlyphKey: (font: CTFont, glyph: CGGlyph)?] = [:]
    private var isRefreshScheduled = false
    /// The cell where the mouse button went down, for a selection by drag.
    private var selectionAnchor: (column: Int, row: Int)?
    /// The part of a scroll that is less than one row.
    private var scrollRemainder: CGFloat = 0
    /// Text that an input method composes, not yet sent to the program.
    private var markedText = ""
    /// The text that the input system made from the key press that is in work. Nil: no key press is in work.
    private var textOfKeyPress: String?

    init(terminal: GhosttyTerminal, fontSize: CGFloat) {
        self.terminal = terminal
        // A font size of 0 comes from tests, which have no settings.
        let fontSize = fontSize > 0 ? fontSize : SettingsKey.standardFontSize
        let regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) as CTFont
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold) as CTFont
        font = regular
        boldFont = bold
        italicFont = CTFontCreateCopyWithSymbolicTraits(regular, 0, nil, .traitItalic, .traitItalic) ?? regular
        boldItalicFont = CTFontCreateCopyWithSymbolicTraits(bold, 0, nil, .traitItalic, .traitItalic) ?? bold
        var glyph = CTFontGetGlyphWithName(regular, "M" as CFString)
        let advance = CTFontGetAdvancesForGlyphs(regular, .horizontal, &glyph, nil, 1)
        let ascent = CTFontGetAscent(regular).rounded(.up)
        let descent = CTFontGetDescent(regular).rounded(.up)
        cellSize = CGSize(width: advance.rounded(.up), height: ascent + descent + CTFontGetLeading(regular).rounded(.up))
        baseline = ascent
        super.init(frame: .zero)
        applyAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerminalView is made in code.") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The size of one cell in the pixels of the display.
    var cellPixelSize: (width: Int, height: Int) {
        let scale = window?.backingScaleFactor ?? 2
        return (Int(cellSize.width * scale), Int(cellSize.height * scale))
    }

    /// Draws the changes of the terminal soon. Many calls in a short time make one draw.
    func scheduleRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8)) { [weak self] in
            self?.isRefreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        for row in terminal.refresh() { setNeedsDisplay(rect(ofRow: row)) }
    }

    // MARK: Size, focus and appearance

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let columns = Int((newSize.width - 2 * Self.padding) / cellSize.width)
        let rows = Int((newSize.height - 2 * Self.padding) / cellSize.height)
        guard columns > 0, rows > 0, columns != terminal.columns || rows != terminal.rowCount else { return }
        terminal.resize(columns: columns, rows: rows, cellWidth: cellPixelSize.width, cellHeight: cellPixelSize.height)
        _ = terminal.refresh()
        needsDisplay = true
        onGridChange?(columns, rows)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        redrawCursor()
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        redrawCursor()
        onFocusChange?(false)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
        _ = terminal.refresh()
        needsDisplay = true
        onColorChange?()
    }

    private func applyAppearanceColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = isDark ? Self.darkColors : Self.lightColors
        terminal.setColors(foreground: colors.foreground, background: colors.background)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        // Shep's menu gets the Command keys.
        guard !event.modifierFlags.contains(.command) else { return super.keyDown(with: event) }
        terminal.scrollToBottom()
        scheduleRefresh()

        // Control and Option change the bytes, not the text, so those keys do not go to the input system.
        let wasComposing = hasMarkedText()
        if wasComposing || event.modifierFlags.isDisjoint(with: [.control, .option]) {
            textOfKeyPress = ""
            interpretKeyEvents([event])
            let text = textOfKeyPress ?? ""
            textOfKeyPress = nil
            if wasComposing || hasMarkedText() {
                // The key press went to the composition. Text that the composition completed goes to the program as it is.
                if !text.isEmpty { onInput?(Data(text.utf8)) }
                return
            }
            if !text.isEmpty {
                send(event, text: text)
                return
            }
        }
        let textFlags = event.modifierFlags.subtracting([.control, .option])
        send(event, text: KeyMapping.text(event.characters(byApplyingModifiers: textFlags)))
    }

    private func send(_ event: NSEvent, text: String) {
        let bytes = terminal.encodeKey(
            KeyMapping.key(forKeyCode: event.keyCode),
            modifiers: KeyMapping.modifiers(event.modifierFlags),
            text: KeyMapping.text(text),
            unshiftedCodepoint: event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0,
            isRepeat: event.isARepeat
        )
        if !bytes.isEmpty { onInput?(bytes) }
    }

    /// The input system calls this for keys that make no text, for example Return. `keyDown` sends those keys.
    override func doCommand(by selector: Selector) {}

    // MARK: Copy and paste

    @objc func copy(_ sender: Any?) {
        guard let text = terminal.selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let bytes = terminal.encodePaste(text)
        if !bytes.isEmpty { onInput?(bytes) }
    }

    override func selectAll(_ sender: Any?) {
        terminal.selectAll()
        refresh()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let cell = cell(at: event)
        switch event.clickCount {
        case 1:
            selectionAnchor = cell
            terminal.clearSelection()
        case 2:
            terminal.selectWord(at: cell)
        default:
            terminal.selectLine(at: cell)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let selectionAnchor else { return }
        terminal.select(from: selectionAnchor, to: cell(at: event))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        selectionAnchor = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * cellSize.height
        scrollRemainder += delta
        let rows = Int(scrollRemainder / cellSize.height)
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows) * cellSize.height
        if terminal.isAlternateScreen {
            // A full-screen program has no history: it gets arrow keys, as other terminals do.
            let key = KeyMapping.key(forKeyCode: rows > 0 ? 126 : 125)
            let bytes = terminal.encodeKey(key, modifiers: [], text: "", unshiftedCodepoint: 0, isRepeat: false)
            onInput?(Data((0..<abs(rows)).flatMap { _ in bytes }))
        } else {
            terminal.scroll(rows: -rows)
            refresh()
        }
    }

    private func cell(at event: NSEvent) -> (column: Int, row: Int) {
        let point = convert(event.locationInWindow, from: nil)
        return (Int((point.x - Self.padding) / cellSize.width), Int((point.y - Self.padding) / cellSize.height))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(terminal.background.cgColor)
        context.fill(dirtyRect)
        context.textMatrix = Self.uprightText
        for (row, cells) in terminal.rows.enumerated() where rect(ofRow: row).intersects(dirtyRect) {
            draw(cells, row: row, in: context)
        }
        if let cursor = terminal.cursor { draw(cursor, in: context) }
    }

    private func draw(_ cells: [TerminalCell], row: Int, in context: CGContext) {
        let top = Self.padding + CGFloat(row) * cellSize.height
        for (column, cell) in cells.enumerated() {
            guard let background = cell.background else { continue }
            context.setFillColor(background.cgColor)
            context.fill(rect(column: column, row: row, isWide: cell.isWide))
        }
        if let selection = terminal.rowSelections[row] {
            context.setFillColor(NSColor.selectedTextBackgroundColor.cgColor)
            let first = rect(column: selection.lowerBound, row: row, isWide: false)
            context.fill(CGRect(x: first.minX, y: first.minY, width: CGFloat(selection.count) * cellSize.width, height: first.height))
        }
        for (column, cell) in cells.enumerated() where !cell.text.isEmpty && cell.text != " " {
            let left = Self.padding + CGFloat(column) * cellSize.width
            let color = cell.foreground.cgColor.copy(alpha: cell.isFaint ? 0.5 : 1) ?? cell.foreground.cgColor
            context.setFillColor(color)
            draw(cell.text, isBold: cell.isBold, isItalic: cell.isItalic, at: CGPoint(x: left, y: top + baseline), in: context)
            let width = cellSize.width * (cell.isWide ? 2 : 1)
            if cell.isUnderlined { context.fill(CGRect(x: left, y: top + baseline + 1, width: width, height: 1)) }
            if cell.isStruckThrough { context.fill(CGRect(x: left, y: top + (cellSize.height / 2).rounded(), width: width, height: 1)) }
        }
    }

    private func draw(_ cursor: TerminalCursor, in context: CGContext) {
        guard cursor.row < terminal.rows.count, cursor.column < terminal.rows[cursor.row].count else { return }
        let cell = terminal.rows[cursor.row][cursor.column]
        let cellRect = rect(column: cursor.column, row: cursor.row, isWide: cell.isWide)
        context.setFillColor(terminal.foreground.cgColor)
        context.setStrokeColor(terminal.foreground.cgColor)
        guard markedText.isEmpty else {
            // The text in composition is at the cursor, with a line below it.
            let width = CGFloat(markedText.count) * cellSize.width * 2
            context.setFillColor(terminal.background.cgColor)
            context.fill(CGRect(x: cellRect.minX, y: cellRect.minY, width: width, height: cellRect.height))
            context.setFillColor(terminal.foreground.cgColor)
            drawLine(markedText, font: font, at: CGPoint(x: cellRect.minX, y: cellRect.minY + baseline), in: context)
            context.fill(CGRect(x: cellRect.minX, y: cellRect.maxY - 1, width: width, height: 1))
            return
        }
        guard window?.firstResponder === self else {
            context.stroke(cellRect.insetBy(dx: 0.5, dy: 0.5), width: 1)
            return
        }
        switch cursor.shape {
        case .bar:
            context.fill(CGRect(x: cellRect.minX, y: cellRect.minY, width: 2, height: cellRect.height))
        case .underline:
            context.fill(CGRect(x: cellRect.minX, y: cellRect.maxY - 2, width: cellRect.width, height: 2))
        case .block:
            context.fill(cellRect)
            context.setFillColor(terminal.background.cgColor)
            draw(cell.text, isBold: cell.isBold, isItalic: cell.isItalic, at: CGPoint(x: cellRect.minX, y: cellRect.minY + baseline), in: context)
        }
    }

    /// Draws the text of one cell. The fill colour of the context is the text colour.
    private func draw(_ text: String, isBold: Bool, isItalic: Bool, at origin: CGPoint, in context: CGContext) {
        guard !text.isEmpty else { return }
        let key = GlyphKey(text: text, isBold: isBold, isItalic: isItalic)
        let cached = glyphs[key] ?? {
            let found = glyph(for: text, in: baseFont(isBold: isBold, isItalic: isItalic))
            glyphs[key] = .some(found)
            return found
        }()
        if let cached {
            var glyph = cached.glyph
            // Glyph positions go through the text matrix, which turns y over.
            var position = CGPoint(x: origin.x, y: -origin.y)
            CTFontDrawGlyphs(cached.font, &glyph, &position, 1, context)
        } else {
            // Text that is not one glyph, for example an emoji sequence: CoreText shapes it.
            drawLine(text, font: baseFont(isBold: isBold, isItalic: isItalic), at: origin, in: context)
        }
    }

    private func drawLine(_ text: String, font: CTFont, at origin: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .init(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        context.textPosition = origin
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        // The line moved the text matrix: put it back for the glyphs that come next.
        context.textMatrix = Self.uprightText
    }

    /// The one glyph of a text, from the base font or from a font that has the character. Nil if the text needs more than one glyph.
    private func glyph(for text: String, in base: CTFont) -> (font: CTFont, glyph: CGGlyph)? {
        guard text.unicodeScalars.count == 1 else { return nil }
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        if CTFontGetGlyphsForCharacters(base, characters, &glyphs, characters.count) { return (base, glyphs[0]) }
        let fallback = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: characters.count))
        if CTFontGetGlyphsForCharacters(fallback, characters, &glyphs, characters.count) { return (fallback, glyphs[0]) }
        return nil
    }

    private func baseFont(isBold: Bool, isItalic: Bool) -> CTFont {
        switch (isBold, isItalic) {
        case (false, false): font
        case (true, false): boldFont
        case (false, true): italicFont
        case (true, true): boldItalicFont
        }
    }

    private func rect(ofRow row: Int) -> CGRect {
        CGRect(x: 0, y: Self.padding + CGFloat(row) * cellSize.height, width: bounds.width, height: cellSize.height)
    }

    private func rect(column: Int, row: Int, isWide: Bool) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(column) * cellSize.width,
            y: Self.padding + CGFloat(row) * cellSize.height,
            width: cellSize.width * (isWide ? 2 : 1),
            height: cellSize.height
        )
    }

    private func redrawCursor() {
        if let cursor = terminal.cursor { setNeedsDisplay(rect(ofRow: cursor.row)) }
    }

    private struct GlyphKey: Hashable {
        var text: String
        var isBold: Bool
        var isItalic: Bool
    }
}

// MARK: - Text input (input methods, dead keys, the emoji picker)

extension TerminalView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        markedText = ""
        redrawCursor()
        if textOfKeyPress != nil {
            textOfKeyPress?.append(text)
        } else if !text.isEmpty {
            // Text that did not come from a key press, for example from the emoji picker.
            onInput?(Data(text.utf8))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        redrawCursor()
    }

    func unmarkText() {
        markedText = ""
        redrawCursor()
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count)
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    /// The place of the cursor on the screen, where the input method shows its window.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let cursor = terminal.cursor, let window else { return .zero }
        return window.convertToScreen(convert(rect(column: cursor.column, row: cursor.row, isWide: false), to: nil))
    }
}

extension TerminalColor {
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// The colour as `#rrggbb`.
    var hex: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }
}
