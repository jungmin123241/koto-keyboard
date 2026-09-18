import XCTest
#if canImport(KeyboardCore)
@testable import KeyboardCore
#endif

final class SettingsTests: XCTestCase {
    func testRoundTripAndValidation() {
        let name = "keyboard-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = KeyboardSettings()
        settings.targetLanguage = "ko"; settings.theme = .dark; settings.delayMilliseconds = 2000
        settings.automaticTranslation = false; settings.wifiOnly = true
        store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.delayMilliseconds, 700)
        XCTAssertEqual(loaded.targetLanguage, "ko")
        XCTAssertEqual(loaded.theme, .dark)
        XCTAssertFalse(loaded.automaticTranslation)
        XCTAssertTrue(loaded.wifiOnly)
    }
    func testMissingContainerAndReadOnlyStore() {
        XCTAssertEqual(SettingsStore(defaults: nil).load(), KeyboardSettings())
        let name = "keyboard-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, writable: false)
        var settings = KeyboardSettings(); settings.translationEnabled = false
        store.save(settings); store.record(error: .timeout)
        XCTAssertNil(defaults.object(forKey: "keyboard.settings.v1"))
        XCTAssertNil(defaults.object(forKey: "keyboard.errorCode"))
    }
}
