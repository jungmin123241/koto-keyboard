import Foundation
import Security

enum SharedConfiguration {
    static var appGroup: String { Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String ?? "" }
    static var keychainGroup: String { Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String ?? "" }
    static var hasSharedContainer: Bool {
        #if FREE_DEVICE_BUILD
        return false
        #else
        return !appGroup.isEmpty && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
        #endif
    }
    static func store(writable: Bool = true) -> SettingsStore {
        #if FREE_DEVICE_BUILD
        // The containing app and extension have separate standard defaults. The keyboard
        // intentionally uses its safe defaults in this no-capability test configuration.
        return SettingsStore(defaults: .standard, writable: writable)
        #else
        guard hasSharedContainer else { return SettingsStore(defaults: nil, writable: false) }
        return SettingsStore(defaults: UserDefaults(suiteName: appGroup), writable: writable)
        #endif
    }
}

enum TokenStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "translation-relay",
         kSecAttrAccount as String: "access-token",
         kSecAttrAccessGroup as String: SharedConfiguration.keychainGroup]
    }
    static func read() -> String? {
        #if FREE_DEVICE_BUILD
        return nil
        #else
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #endif
    }
    @discardableResult static func save(_ token: String) -> Bool {
        #if FREE_DEVICE_BUILD
        return false
        #else
        if token.isEmpty { let result = SecItemDelete(query as CFDictionary); return result == errSecSuccess || result == errSecItemNotFound }
        let data = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        #endif
    }
}

enum TranslationServiceFactory {
    static func make(settings: KeyboardSettings, fullAccess: Bool) throws -> any TranslationService {
        switch settings.service {
        case .mock: return MockTranslationService()
        case .local: return LocalTranslationService()
        case .remote:
            guard fullAccess else { throw TranslationError.permission }
            guard settings.networkConsent, let endpoint = URL(string: settings.remoteEndpoint),
                  endpoint.scheme == "https", endpoint.host != nil,
                  let token = TokenStore.read(), !token.isEmpty else { throw TranslationError.configuration }
            return RemoteTranslationService(endpoint: endpoint, accessToken: token, wifiOnly: settings.wifiOnly)
        }
    }
}
