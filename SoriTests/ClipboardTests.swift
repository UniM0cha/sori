// Note: Clipboard.writeAndPaste is intentionally NOT covered here. It posts a
// system-wide Cmd-V via CGEventPost, which is meaningless under xcodebuild test
// (no focused text field) and would pollute whatever app has focus. We only
// verify the writeOnly path, which is the pasteboard interaction a unit test
// can observe deterministically.

import AppKit
import XCTest
@testable import Sori

final class ClipboardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    func testWriteOnlySetsStringOnPasteboard() {
        Clipboard.writeOnly("안녕하세요")

        let result = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(result, "안녕하세요")
    }

    func testWriteOnlyOverwritesPreviousContents() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("old", forType: .string)

        Clipboard.writeOnly("new")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "new")
    }

    func testWriteOnlyHandlesEmptyString() {
        Clipboard.writeOnly("")
        // An empty string is a valid pasteboard value — the API should not crash
        // and NSPasteboard should return "" (not nil).
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "")
    }

    func testWriteOnlySupportsMultilineText() {
        let text = "첫 줄\n둘째 줄\n셋째 줄"
        Clipboard.writeOnly(text)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), text)
    }
}
