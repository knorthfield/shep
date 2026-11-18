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
}
