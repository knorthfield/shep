import Foundation
import os

/// One terminal of the core that Shep shows: the screen state, the view and the attach stream.
@MainActor
final class TerminalSession {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shep", category: "TerminalSession")
    private static let historyRows = 2000

    let address: String
    let view: TerminalView
    /// The view of this terminal got the keyboard.
    var onBecameFocused: (() -> Void)?

    private let terminal: GhosttyTerminal
    private let connection: CoreConnection
    private var channel: UInt32?
    private var isAttaching = false
    /// True when the core accepts the terminal's own answers as a different kind of frame than typed input.
    private var sendsAutomaticInput = false

    init?(address: String, connection: CoreConnection) {
        guard let terminal = GhosttyTerminal(columns: 80, rows: 24) else { return nil }
        self.address = address
        self.connection = connection
        self.terminal = terminal
        view = TerminalView(
            terminal: terminal,
            fontName: UserDefaults.standard.string(forKey: SettingsKey.fontName) ?? "",
            fontSize: UserDefaults.standard.double(forKey: SettingsKey.fontSize)
        )
        view.onInput = { [weak self] bytes in self?.send(.data, bytes) }
        view.onFileDrop = { [weak self] urls in self?.drop(urls) }
        view.onFocusChange = { [weak self] hasFocus in
            self?.send(.focus, Data([hasFocus ? 1 : 0]))
            if hasFocus { self?.onBecameFocused?() }
        }
        view.onColorChange = { [weak self] in
            guard let self else { return }
            send(.facts, displayFacts.encoded())
        }
        view.onGridChange = { [weak self] columns, rows in
            self?.gridDidChange(columns: columns, rows: rows)
        }
    }

    /// Stops the stream. The terminal continues in the core.
    func detach() {
        send(.close, Data())
        channel = nil
    }

    /// Attaches again after the core gave the terminal a new shell. The core sends the full screen again.
    func reattach() {
        detach()
        terminal.write(Data("\u{1B}c".utf8))
        startAttach()
    }

    /// What the core tells a program that asks for the colours or the cell size of its terminal.
    private var displayFacts: JSONValue {
        [
            "fg": .string(terminal.foreground.hex),
            "bg": .string(terminal.background.hex),
            "cursor": .string(terminal.foreground.hex),
            "cell": [.int(Int64(view.cellPixelSize.width)), .int(Int64(view.cellPixelSize.height))],
        ]
    }

    private func send(_ kind: FrameKind, _ payload: Data) {
        guard let channel else { return }
        connection.send(kind, channel: channel, payload)
    }

    /// The first size of the view starts the attach. Each size after that goes to the core.
    private func gridDidChange(columns: Int, rows: Int) {
        if channel != nil {
            var payload = Data()
            payload.appendLittleEndian(UInt16(columns))
            payload.appendLittleEndian(UInt16(rows))
            send(.resize, payload)
        } else {
            startAttach()
        }
    }

    private func startAttach() {
        guard !isAttaching else { return }
        isAttaching = true
        Task { await attach() }
    }

    private func attach() async {
        defer { isAttaching = false }
        do {
            let (columns, rows) = (terminal.columns, terminal.rowCount)
            let result = try await connection.call("terminal.attach", [
                "terminal": .string(address),
                "cols": .int(Int64(columns)),
                "rows": .int(Int64(rows)),
                "history": .int(Int64(Self.historyRows)),
                "display": displayFacts,
            ])
            guard let channel = result["channel"].int.map(UInt32.init) else { return }
            self.channel = channel
            sendsAutomaticInput = connection.hello.features.contains("automatic_input") && result["automatic_input"].bool == true
            // The view can get a new size during the call.
            if (columns, rows) != (terminal.columns, terminal.rowCount) {
                gridDidChange(columns: terminal.columns, rows: terminal.rowCount)
            }
            send(.focus, Data([view.window?.firstResponder === view ? 1 : 0]))
            Task { await read(channel) }
        } catch {
            Self.logger.error("Attach to \(self.address) failed: \(error)")
            show(notice: (error as? CoreError)?.message ?? "Shep cannot attach to this terminal.")
        }
    }

    private func read(_ channel: UInt32) async {
        for await event in connection.stream(channel) {
            switch event {
            case .data(let bytes):
                terminal.write(bytes)
                let replies = terminal.takeReplies()
                if !replies.isEmpty { connection.send(sendsAutomaticInput ? .automaticInput : .data, channel: channel, replies) }
                connection.credit(channel, bytes: bytes.count)
                view.scheduleRefresh()
            case .close(let reason):
                // The stream that this session uses now ended, for example because the program ended.
                guard self.channel == channel else { continue }
                self.channel = nil
                if let word = reason["reason"].string { show(notice: "The program stopped (\(word)).") }
            case .resize:
                break
            }
        }
    }

    // MARK: File drop

    /// Pastes the paths of dropped files. A terminal on a machine gets a copy of each file, and the path of the copy there.
    private func drop(_ urls: [URL]) {
        guard address.contains("/") else {
            return paste(paths: urls.map { DroppedFiles.isTemporaryScreenshot($0) ? (keptCopy(of: $0) ?? $0).path : $0.path })
        }
        Task {
            var paths: [String] = []
            for url in urls {
                do {
                    paths.append(try await sendToMachine(url))
                } catch {
                    let reason = (error as? CoreError)?.message ?? error.localizedDescription
                    show(notice: "Shep cannot send \(url.lastPathComponent): \(reason)")
                }
            }
            if !paths.isEmpty { paste(paths: paths) }
        }
    }

    private func paste(paths: [String]) {
        guard let text = DroppedFiles.pasteText(forPaths: paths) else {
            return show(notice: "Shep cannot paste a path that has a control character.")
        }
        view.paste(text: text)
    }

    /// Copies the file of a screenshot thumbnail to a folder where it stays. macOS deletes the initial file after a few seconds.
    private func keptCopy(of url: URL) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "shep-drops")
        let copy = folder.appending(path: "\(Int(Date().timeIntervalSince1970 * 1000))-\(url.lastPathComponent)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        } catch {
            Self.logger.error("Copy of \(url.path) failed: \(error)")
            return nil
        }
    }

    /// Sends a file to the machine of this terminal and returns its path there.
    private func sendToMachine(_ url: URL) async throws -> String {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory != true else { throw DropError.folder }
        guard (values.fileSize ?? 0) <= DroppedFiles.largestSentFile else { throw DropError.tooLarge }
        let data = try Data(contentsOf: url)
        let result = try await connection.call("terminal.put", [
            "terminal": .string(address),
            "name": .string(url.lastPathComponent),
            "data": .string(data.base64EncodedString()),
        ], timeout: .seconds(60))
        guard let path = result["path"].string else { throw DropError.noPath }
        return path
    }

    private enum DropError: LocalizedError {
        case folder, tooLarge, noPath

        var errorDescription: String? {
            switch self {
            case .folder: "a folder cannot go to another machine."
            case .tooLarge: "the file is larger than 8 MB."
            case .noPath: "the machine gave no path."
            }
        }
    }

    /// Writes a faint line of Shep's own text on the terminal screen.
    private func show(notice: String) {
        terminal.write(Data("\r\n\u{1B}[0;2m[\(notice)]\u{1B}[0m\r\n".utf8))
        view.scheduleRefresh()
    }
}
