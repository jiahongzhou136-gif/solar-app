import Foundation

/// 主 App 与 Widget 共享配置。
///
/// 免费签名下 Sideloadly 会重签 bundle id，并可能给 App Group 加 Team 前缀，
/// 因此这里三条通道并写，任意一条可读即生效：
///  1) UserDefaults.standard（App 自身设置页）
///  2) App Group —— 同时尝试无前缀与 Team 前缀两种 suite
///  3) Keychain（无 access group）
enum SharedConfig {
    static let keyURL = "solar.ha.url"
    static let keyToken = "solar.ha.token"
    static let legacyURL = "haURL"
    static let legacyToken = "haToken"

    /// 动态枚举可能的 suite：Sideloadly 会把 group id 改成 <TEAMID>.group.xxx
    private static var candidateSuites: [String] {
        var out = ["group.com.zhoujh.solar"]
        if let bid = Bundle.main.bundleIdentifier {
            let parts = bid.split(separator: ".").map(String.init)
            if let team = parts.first, !team.isEmpty {
                out.append("\(team).group.com.zhoujh.solar")
            }
        }
        return out
    }

    private static func readGroup(_ key: String) -> String {
        for suite in candidateSuites {
            if let d = UserDefaults(suiteName: suite), let v = d.string(forKey: key), !v.isEmpty {
                return v
            }
        }
        return ""
    }

    private static func writeGroup(_ value: String, key: String) {
        for suite in candidateSuites {
            UserDefaults(suiteName: suite)?.set(value, forKey: key)
        }
    }

    // MARK: Keychain

    private static func keyQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.zhoujh.solar.widget",
        ]
    }

    private static func keychainSet(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q = keyQuery(key)
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainGet(_ key: String) -> String {
        var q = keyQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: 公开接口

    static func save(url: String, token: String) {
        UserDefaults.standard.set(url, forKey: legacyURL)
        UserDefaults.standard.set(token, forKey: legacyToken)
        writeGroup(url, key: keyURL)
        writeGroup(token, key: keyToken)
        keychainSet(url, forKey: keyURL)
        keychainSet(token, forKey: keyToken)
    }

    static var url: String {
        for v in [readGroup(keyURL), keychainGet(keyURL),
                  UserDefaults.standard.string(forKey: legacyURL) ?? ""] {
            if !v.isEmpty { return v }
        }
        return ""
    }

    static var token: String {
        for v in [readGroup(keyToken), keychainGet(keyToken),
                  UserDefaults.standard.string(forKey: legacyToken) ?? ""] {
            if !v.isEmpty { return v }
        }
        return ""
    }

    static var configured: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
