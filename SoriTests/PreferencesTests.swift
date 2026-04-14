import XCTest
@testable import Sori

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.solstice.sori.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        UserDefaults.registerSoriDefaults(on: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreRegistered() {
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.modelId, ModelIdentifier.defaultModel)
        XCTAssertEqual(snapshot.modelIdleTimeoutSeconds, 300.0)
        XCTAssertEqual(snapshot.asrLanguage, "auto")
        XCTAssertEqual(snapshot.customWords, "")
        XCTAssertEqual(snapshot.historyMaxEntries, 1000)
        XCTAssertEqual(snapshot.historyRetentionDays, 0)
        XCTAssertFalse(snapshot.eagerLoadModelOnLaunch)
        XCTAssertFalse(snapshot.hasCompletedWelcome)
    }

    func testCustomModelIdIsPersisted() {
        defaults.set("mlx-community/Qwen3-ASR-0.6B-4bit", forKey: PreferenceKeys.modelId)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.modelId, "mlx-community/Qwen3-ASR-0.6B-4bit")
    }

    func testIdleTimeoutFallbackWhenZero() {
        defaults.set(0.0, forKey: PreferenceKeys.modelIdleTimeoutSeconds)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.modelIdleTimeoutSeconds, 300.0)
    }

    func testIdleTimeoutKeepsExplicitValue() {
        defaults.set(600.0, forKey: PreferenceKeys.modelIdleTimeoutSeconds)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.modelIdleTimeoutSeconds, 600.0)
    }

    func testHistoryMaxEntriesFallback() {
        defaults.set(0, forKey: PreferenceKeys.historyMaxEntries)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.historyMaxEntries, 1000)
    }

    func testCustomWordsAndLanguageRoundTrip() {
        defaults.set("Xcode, SwiftUI, 카카오톡", forKey: PreferenceKeys.customWords)
        defaults.set("ko", forKey: PreferenceKeys.asrLanguage)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertEqual(snapshot.customWords, "Xcode, SwiftUI, 카카오톡")
        XCTAssertEqual(snapshot.asrLanguage, "ko")
    }

    func testEagerLoadToggleRoundTrip() {
        defaults.set(true, forKey: PreferenceKeys.eagerLoadModelOnLaunch)
        let snapshot = PreferencesSnapshot(defaults: defaults)
        XCTAssertTrue(snapshot.eagerLoadModelOnLaunch)
    }
}
