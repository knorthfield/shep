import AppKit
import GhosttyVt

/// Changes a key press of macOS into the values that the key encoder of libghostty-vt uses.
enum KeyMapping {
    /// The physical key of a macOS virtual key code.
    static func key(forKeyCode keyCode: UInt16) -> GhosttyKey {
        keysByKeyCode[keyCode] ?? GHOSTTY_KEY_UNIDENTIFIED
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// The text of a key press for the encoder: no control characters and no function-key codes of macOS.
    static func text(_ characters: String?) -> String {
        guard let characters, let first = characters.unicodeScalars.first else { return "" }
        let isControl = first.value < 0x20 || first.value == 0x7F
        let isFunctionKey = (0xF700...0xF8FF).contains(first.value)
        return isControl || isFunctionKey ? "" : characters
    }

    private static let keysByKeyCode: [UInt16: GhosttyKey] = [
        0: GHOSTTY_KEY_A, 1: GHOSTTY_KEY_S, 2: GHOSTTY_KEY_D, 3: GHOSTTY_KEY_F, 4: GHOSTTY_KEY_H, 5: GHOSTTY_KEY_G,
        6: GHOSTTY_KEY_Z, 7: GHOSTTY_KEY_X, 8: GHOSTTY_KEY_C, 9: GHOSTTY_KEY_V, 10: GHOSTTY_KEY_INTL_BACKSLASH,
        11: GHOSTTY_KEY_B, 12: GHOSTTY_KEY_Q, 13: GHOSTTY_KEY_W, 14: GHOSTTY_KEY_E, 15: GHOSTTY_KEY_R,
        16: GHOSTTY_KEY_Y, 17: GHOSTTY_KEY_T, 18: GHOSTTY_KEY_DIGIT_1, 19: GHOSTTY_KEY_DIGIT_2,
        20: GHOSTTY_KEY_DIGIT_3, 21: GHOSTTY_KEY_DIGIT_4, 22: GHOSTTY_KEY_DIGIT_6, 23: GHOSTTY_KEY_DIGIT_5,
        24: GHOSTTY_KEY_EQUAL, 25: GHOSTTY_KEY_DIGIT_9, 26: GHOSTTY_KEY_DIGIT_7, 27: GHOSTTY_KEY_MINUS,
        28: GHOSTTY_KEY_DIGIT_8, 29: GHOSTTY_KEY_DIGIT_0, 30: GHOSTTY_KEY_BRACKET_RIGHT, 31: GHOSTTY_KEY_O,
        32: GHOSTTY_KEY_U, 33: GHOSTTY_KEY_BRACKET_LEFT, 34: GHOSTTY_KEY_I, 35: GHOSTTY_KEY_P,
        36: GHOSTTY_KEY_ENTER, 37: GHOSTTY_KEY_L, 38: GHOSTTY_KEY_J, 39: GHOSTTY_KEY_QUOTE, 40: GHOSTTY_KEY_K,
        41: GHOSTTY_KEY_SEMICOLON, 42: GHOSTTY_KEY_BACKSLASH, 43: GHOSTTY_KEY_COMMA, 44: GHOSTTY_KEY_SLASH,
        45: GHOSTTY_KEY_N, 46: GHOSTTY_KEY_M, 47: GHOSTTY_KEY_PERIOD, 48: GHOSTTY_KEY_TAB, 49: GHOSTTY_KEY_SPACE,
        50: GHOSTTY_KEY_BACKQUOTE, 51: GHOSTTY_KEY_BACKSPACE, 53: GHOSTTY_KEY_ESCAPE,
        65: GHOSTTY_KEY_NUMPAD_DECIMAL, 67: GHOSTTY_KEY_NUMPAD_MULTIPLY, 69: GHOSTTY_KEY_NUMPAD_ADD,
        71: GHOSTTY_KEY_NUMPAD_CLEAR, 75: GHOSTTY_KEY_NUMPAD_DIVIDE, 76: GHOSTTY_KEY_NUMPAD_ENTER,
        78: GHOSTTY_KEY_NUMPAD_SUBTRACT, 81: GHOSTTY_KEY_NUMPAD_EQUAL, 82: GHOSTTY_KEY_NUMPAD_0,
        83: GHOSTTY_KEY_NUMPAD_1, 84: GHOSTTY_KEY_NUMPAD_2, 85: GHOSTTY_KEY_NUMPAD_3, 86: GHOSTTY_KEY_NUMPAD_4,
        87: GHOSTTY_KEY_NUMPAD_5, 88: GHOSTTY_KEY_NUMPAD_6, 89: GHOSTTY_KEY_NUMPAD_7, 91: GHOSTTY_KEY_NUMPAD_8,
        92: GHOSTTY_KEY_NUMPAD_9,
        96: GHOSTTY_KEY_F5, 97: GHOSTTY_KEY_F6, 98: GHOSTTY_KEY_F7, 99: GHOSTTY_KEY_F3, 100: GHOSTTY_KEY_F8,
        101: GHOSTTY_KEY_F9, 103: GHOSTTY_KEY_F11, 109: GHOSTTY_KEY_F10, 111: GHOSTTY_KEY_F12,
        114: GHOSTTY_KEY_INSERT, 115: GHOSTTY_KEY_HOME, 116: GHOSTTY_KEY_PAGE_UP, 117: GHOSTTY_KEY_DELETE,
        118: GHOSTTY_KEY_F4, 119: GHOSTTY_KEY_END, 120: GHOSTTY_KEY_F2, 121: GHOSTTY_KEY_PAGE_DOWN,
        122: GHOSTTY_KEY_F1, 123: GHOSTTY_KEY_ARROW_LEFT, 124: GHOSTTY_KEY_ARROW_RIGHT,
        125: GHOSTTY_KEY_ARROW_DOWN, 126: GHOSTTY_KEY_ARROW_UP,
    ]
}
