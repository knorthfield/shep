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
