import XCTest
@testable import Sori

final class HistoryEntryTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testLiveSourceRoundTrip() throws {
        let original = HistoryEntry(
            text: "오늘 회의록을 정리해 주세요",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 4.2,
            source: .live
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds, accuracy: 0.001)
        XCTAssertEqual(decoded.source, .live)
        XCTAssertFalse(decoded.isFileSource)
        XCTAssertNil(decoded.originalFilePath)
    }

    func testFileSourceRoundTrip() throws {
        let path = "/Users/me/Downloads/interview.m4a"
        let original = HistoryEntry(
            text: "Swift concurrency 이야기",
            durationSeconds: 0,
            source: .file(bookmark: nil, originalPath: path)
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HistoryEntry.self, from: data)
        XCTAssertTrue(decoded.isFileSource)
        XCTAssertEqual(decoded.originalFilePath, path)
    }

    func testPreviewReturnsShortTextUnchanged() {
        let entry = HistoryEntry(text: "짧은 텍스트", durationSeconds: 1)
        XCTAssertEqual(entry.preview, "짧은 텍스트")
    }

    func testPreviewTruncatesLongText() {
        let long = String(repeating: "가", count: 200)
        let entry = HistoryEntry(text: long, durationSeconds: 1)
        XCTAssertTrue(entry.preview.hasSuffix("…"))
        XCTAssertEqual(entry.preview.count, 81)
    }

    func testPreviewTrimsWhitespace() {
        let entry = HistoryEntry(text: "   여유   ", durationSeconds: 1)
        XCTAssertEqual(entry.preview, "여유")
    }

    func testCharacterCountMatchesTextLength() {
        let text = "abc 가나다"
        let entry = HistoryEntry(text: text, durationSeconds: 0)
        XCTAssertEqual(entry.characterCount, text.count)
    }
}
