import XCTest
@testable import Sori

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sori-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    private func makeStore(maxEntries: Int = 1000) -> HistoryStore {
        let fileURL = tempDirectory.appendingPathComponent("history.json")
        return HistoryStore(fileURL: fileURL, maxEntries: maxEntries)
    }

    func testAppendIncrementsAndOrders() {
        let store = makeStore()
        store.append(text: "첫 번째", duration: 1)
        store.append(text: "두 번째", duration: 2)
        store.append(text: "세 번째", duration: 3)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].text, "세 번째")
        XCTAssertEqual(store.entries[2].text, "첫 번째")
    }

    func testFifoTrimsBeyondMax() {
        let store = makeStore(maxEntries: 3)
        store.append(text: "1", duration: 0)
        store.append(text: "2", duration: 0)
        store.append(text: "3", duration: 0)
        store.append(text: "4", duration: 0)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].text, "4")
        XCTAssertEqual(store.entries[2].text, "2")
        XCTAssertFalse(store.entries.contains { $0.text == "1" })
    }

    func testRemoveByID() {
        let store = makeStore()
        store.append(text: "a", duration: 0)
        store.append(text: "b", duration: 0)
        store.append(text: "c", duration: 0)
        let target = store.entries[1].id

        store.remove(id: target)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertFalse(store.entries.contains { $0.id == target })
    }

    func testClearEmptiesEverything() {
        let store = makeStore()
        store.append(text: "a", duration: 0)
        store.append(text: "b", duration: 0)

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testBumpMovesToFront() {
        let store = makeStore()
        store.append(text: "a", duration: 0)
        store.append(text: "b", duration: 0)
        store.append(text: "c", duration: 0)
        let oldest = store.entries.last!.id

        store.bump(id: oldest)

        XCTAssertEqual(store.entries.first?.id, oldest)
    }

    func testSearchCaseInsensitiveContains() {
        let store = makeStore()
        store.append(text: "Hello World", duration: 0)
        store.append(text: "안녕 하세요", duration: 0)
        store.append(text: "swift 6 concurrency", duration: 0)

        XCTAssertEqual(store.search(query: "HELLO").count, 1)
        XCTAssertEqual(store.search(query: "안녕").count, 1)
        XCTAssertEqual(store.search(query: "Swift").count, 1)
        XCTAssertEqual(store.search(query: "없는단어").count, 0)
    }

    func testSearchEmptyQueryReturnsAll() {
        let store = makeStore()
        store.append(text: "a", duration: 0)
        store.append(text: "b", duration: 0)

        XCTAssertEqual(store.search(query: "").count, 2)
        XCTAssertEqual(store.search(query: "   ").count, 2)
    }

    func testPersistenceAcrossInstances() {
        let store1 = makeStore()
        store1.append(text: "저장될 텍스트", duration: 1.23)
        let savedId = store1.entries.first!.id

        let store2 = makeStore()
        XCTAssertEqual(store2.entries.count, 1)
        XCTAssertEqual(store2.entries.first?.id, savedId)
        XCTAssertEqual(store2.entries.first?.text, "저장될 텍스트")
    }

    func testCorruptedFileIsRecovered() throws {
        let fileURL = tempDirectory.appendingPathComponent("history.json")
        try Data("not valid json".utf8).write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL, maxEntries: 1000)

        XCTAssertTrue(store.entries.isEmpty)
        // A backup file should have been created in the same directory
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        )
        let hasBackup = contents.contains { $0.lastPathComponent.contains("backup") }
        XCTAssertTrue(hasBackup)
    }
}
