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
