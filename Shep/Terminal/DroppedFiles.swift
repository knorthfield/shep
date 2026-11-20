import Foundation

/// Files that the user dropped on a terminal: their paths go to the program as a paste.
enum DroppedFiles {
    /// The core refuses a larger file in `terminal.put`.
    static let largestSentFile = 8 * 1024 * 1024
    private static let charactersThatNeedNoQuotes = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:@%~,")

    /// The paths as a POSIX shell reads them, with a space after the last one and no Return.
    /// Nil if there is no path, or if a path has a control character: a new line is Return in a paste that is not bracketed.
    static func pasteText(forPaths paths: [String]) -> String? {
        guard !paths.isEmpty else { return nil }
        var words: [String] = []
        for path in paths {
            guard !path.isEmpty, !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
            if path.allSatisfy(charactersThatNeedNoQuotes.contains) {
                words.append(path)
            } else {
                words.append("'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'")
            }
        }
        return words.joined(separator: " ") + " "
    }

    /// True for the file of the screenshot thumbnail that macOS shows in the corner of the screen.
    /// macOS deletes this file a few seconds after the drop.
    static func isTemporaryScreenshot(_ url: URL) -> Bool {
        url.path.contains("TemporaryItems/NSIRD_screencaptureui")
    }
}
