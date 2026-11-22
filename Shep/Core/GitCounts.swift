import Foundation

/// The commits of the branch in a folder that its upstream does not have (ahead, not pushed),
/// and the commits of the upstream that the branch does not have (behind).
struct GitCounts: Equatable {
    var ahead: Int
    var behind: Int

    /// Reads only the refs, as Herdr does: it does not scan the work tree.
    static let command = ["git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}"]

    /// From the result of `machine.exec` for `command`. Nil: the folder is not in a repository, or the branch has no upstream.
    init?(execResult: JSONValue) {
        guard execResult["code"].int == 0,
              let data = execResult["stdout"].string.flatMap({ Data(base64Encoded: $0) }) else { return nil }
        let counts = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard counts.count == 2 else { return nil }
        ahead = counts[0]
        behind = counts[1]
    }
}

/// The commits since the newest tag that HEAD can reach: the commits that are not released.
struct CommitsSinceRelease: Equatable {
    var tag: String
    var count: Int

    /// Reads only the refs: it does not scan the work tree.
    static let command = ["git", "describe", "--tags", "--long"]

    /// From the result of `machine.exec` for `command`: "<tag>-<count>-g<hash>". A tag can contain "-".
    /// Nil: the folder is not in a repository, or HEAD can reach no tag.
    init?(execResult: JSONValue) {
        guard execResult["code"].int == 0,
              let data = execResult["stdout"].string.flatMap({ Data(base64Encoded: $0) }) else { return nil }
        var parts = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.removeLast().hasPrefix("g"), let count = Int(parts.removeLast()) else { return nil }
        tag = parts.joined(separator: "-")
        self.count = count
    }
}
