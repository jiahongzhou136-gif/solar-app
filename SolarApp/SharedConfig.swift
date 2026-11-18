import Foundation
import Security

/// 主 App 与 Widget 共享配置。
/// 免费签名下 Sideloadly 常剥离 App Group entitlement，因此优先用 Keychain
/// （同一 Team 签发的 App 与 Extension 默认共享 Keychain，无需额外 entitlement）。
enum SharedConfig {
    static let keyURL = "solar.ha.url"
    static let keyToken = "solar.ha.token"

    // MARK: Keychain

    private static func keychainSet(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.zhoujh.solar.widget",
        ]
        // 先删旧值
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainGet(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.zhoujh.solar.widget",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: 公开接口

    static func save(url: String, token: String) {
        keychainSet(url, forKey: keyURL)
        keychainSet(token, forKey: keyToken)
    }

    static var url: String { keychainGet(keyURL) }
    static var token: String { keychainGet(keyToken) }
    static var configured: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
