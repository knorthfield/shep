import XCTest
@testable import Shep

final class DroppedFilesTests: XCTestCase {
    func testPathWithOnlySafeCharactersHasNoQuotes() {
        XCTAssertEqual(DroppedFiles.pasteText(forPaths: ["/tmp/shot.png"]), "/tmp/shot.png ")
        XCTAssertEqual(DroppedFiles.pasteText(forPaths: ["/tmp/a,b.txt"]), "/tmp/a,b.txt ")
    }

    func testPathWithSpaceHasQuotes() {
        XCTAssertEqual(DroppedFiles.pasteText(forPaths: ["/tmp/my shot.png", "/a/b"]), "'/tmp/my shot.png' /a/b ")
    }

    func testApostropheIsEscaped() {
        XCTAssertEqual(DroppedFiles.pasteText(forPaths: ["/tmp/it's.png"]), "'/tmp/it'\\''s.png' ")
    }

    func testPathThatIsNotASCIIHasQuotes() {
        XCTAssertEqual(DroppedFiles.pasteText(forPaths: ["/work/中文.txt"]), "'/work/中文.txt' ")
    }

    func testControlCharacterOrNoPathGivesNoText() {
        for path in ["/work/a\nb", "/work/a\rb", "/work/\u{1B}[201~", "/work/\tfile", "/work/\u{7F}file", ""] {
            XCTAssertNil(DroppedFiles.pasteText(forPaths: [path]), path.debugDescription)
            XCTAssertNil(DroppedFiles.pasteText(forPaths: ["/work/safe.txt", path]), path.debugDescription)
        }
        XCTAssertNil(DroppedFiles.pasteText(forPaths: []))
    }

    func testTemporaryScreenshot() {
        let thumbnail = URL(fileURLWithPath: "/var/folders/ab/T/TemporaryItems/NSIRD_screencaptureui_x1/Screenshot 2026-11-20.png")
        XCTAssertTrue(DroppedFiles.isTemporaryScreenshot(thumbnail))
        XCTAssertFalse(DroppedFiles.isTemporaryScreenshot(URL(fileURLWithPath: "/Users/me/Desktop/Screenshot 2026-11-20.png")))
    }
}
