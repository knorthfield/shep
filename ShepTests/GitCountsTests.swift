import Foundation
import Testing
@testable import Shep

struct GitCountsTests {
    private func result(code: Int64, stdout: String) -> JSONValue {
        ["code": .int(code), "stdout": .string(Data(stdout.utf8).base64EncodedString()), "stderr": ""]
    }

    @Test func theCountsAreAheadThenBehind() {
        let counts = GitCounts(execResult: result(code: 0, stdout: "3\t1\n"))
        #expect(counts?.ahead == 3)
        #expect(counts?.behind == 1)
    }

    @Test func aFolderWithoutARepositoryOrAnUpstreamHasNoCounts() {
        #expect(GitCounts(execResult: result(code: 128, stdout: "")) == nil)
        #expect(GitCounts(execResult: result(code: 0, stdout: "")) == nil)
    }
}

struct CommitsSinceReleaseTests {
    private func result(code: Int64, stdout: String) -> JSONValue {
        ["code": .int(code), "stdout": .string(Data(stdout.utf8).base64EncodedString()), "stderr": ""]
    }

    @Test func theTagAndTheCountComeFromTheDescription() {
        let release = CommitsSinceRelease(execResult: result(code: 0, stdout: "v0.10-5-gd16d7ae\n"))
        #expect(release?.tag == "v0.10")
        #expect(release?.count == 5)
    }

    @Test func aTagCanContainHyphens() {
        let release = CommitsSinceRelease(execResult: result(code: 0, stdout: "release-1.2-3-gabc\n"))
        #expect(release?.tag == "release-1.2")
        #expect(release?.count == 3)
    }

    @Test func aFolderWithoutATagHasNoCount() {
        #expect(CommitsSinceRelease(execResult: result(code: 128, stdout: "")) == nil)
    }
}
