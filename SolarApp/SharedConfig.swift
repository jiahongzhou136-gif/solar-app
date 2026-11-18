import Foundation

/// 主 App 与 Widget 通过 App Group 共享配置（地址/令牌只在 App 设置页填一次）
enum SharedConfig {
    static let suiteName = "group.com.zhoujh.solar"
    static let keyURL = "haURL"
    static let keyToken = "haToken"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func save(url: String, token: String) {
        let d = defaults
        d?.set(url, forKey: keyURL)
        d?.set(token, forKey: keyToken)
    }

    static var url: String { defaults?.string(forKey: keyURL) ?? "" }
    static var token: String { defaults?.string(forKey: keyToken) ?? "" }
    static var configured: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
