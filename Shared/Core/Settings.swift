import Foundation

public enum ServiceKind: String, Codable, CaseIterable, Sendable { case mock, local, remote }
public enum KeyboardTheme: String, Codable, CaseIterable, Sendable { case system, light, dark }

public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var translationEnabled = true
    public var targetLanguage = "ja"
    public var service: ServiceKind = .mock
    public var automaticTranslation = true
    public var delayMilliseconds = 550
    public var wifiOnly = false
    public var hapticFeedback = false
    public var theme: KeyboardTheme = .system
    public var remoteEndpoint = ""
    public var networkConsent = false
    public init() {}

    public mutating func sanitize() {
        delayMilliseconds = min(700, max(400, delayMilliseconds))
        if !["ja", "ko", "en", "zh"].contains(targetLanguage) { targetLanguage = "ja" }
    }
}

public final class SettingsStore {
    private let defaults: UserDefaults?
    private let writable: Bool
    private let key = "keyboard.settings.v1"
    public init(defaults: UserDefaults?, writable: Bool = true) {
        self.defaults = defaults
        self.writable = writable
    }
    public func load() -> KeyboardSettings {
        guard let data = defaults?.data(forKey: key), var value = try? JSONDecoder().decode(KeyboardSettings.self, from: data) else {
            return KeyboardSettings()
        }
        value.sanitize()
        return value
    }
    public func save(_ value: KeyboardSettings) {
        guard writable else { return }
        var clean = value
        clean.sanitize()
        defaults?.set(try? JSONEncoder().encode(clean), forKey: key)
    }
    public func record(error: TranslationError?) {
        guard writable else { return }
        defaults?.set(error?.rawValue, forKey: "keyboard.errorCode")
    }
}
