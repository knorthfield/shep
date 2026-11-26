import Foundation

/// Finds the `hc` command of herdr-core.
enum HcBinary {
    static let installCommand = "curl -fsSL https://releases.herdr.dev/core/install.sh | sh"

    /// The first `hc` that exists: the path from Settings, then the folders of `PATH`, then the usual install folders.
    /// An app that Finder starts has a short `PATH`, thus the usual folders are necessary.
    static func find(
        configuredPath: String?,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL? {
        var candidates: [String] = []
        if let configuredPath, !configuredPath.isEmpty { candidates.append(configuredPath) }
        candidates += (environmentPath ?? "").split(separator: ":").map { "\($0)/hc" }
        candidates += [
            home.appending(path: ".local/bin/hc").path,
            "/opt/homebrew/bin/hc",
            "/usr/local/bin/hc",
            home.appending(path: ".cargo/bin/hc").path,
        ]
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    /// The error of `hc machine add --json`, from all that it printed. Nil if hc added the machine.
    static func machineAddError(inOutput output: Data) -> String? {
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastLine = text.split(whereSeparator: \.isNewline).last else { return "hc gave no answer." }
        guard let reply = JSONValue(json: Data(lastLine.utf8)) else { return text }
        let error = reply["error"]
        guard !error.isNull else { return nil }
        return CoreError(message: error["message"].string ?? text, hint: error["hint"].string).text
    }
}
