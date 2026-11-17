import Foundation

// MARK: - 配置

enum SolarConfig {
    /// 示例地址；首次启动在 App 设置页填自己的 HA 地址
    static let defaultBaseURL = "http://192.168.1.100:8123"
    static let defaultPanelURL = "http://192.168.1.100:8123/solar-board/solar"

    /// 一次模板请求取回全部数值，避免 6 次 HTTP 往返
    static let entities: [(String, String)] = [
        ("pv",       "sensor.guang_fu_ben_di_wang_guan_pv1_power"),
        ("daily",    "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy"),
        ("total",    "sensor.guang_fu_ben_di_wang_guan_total_pv_energy"),
        ("load",     "sensor.guang_fu_ben_di_wang_guan_load_power"),
        ("soc",      "sensor.guang_fu_ben_di_wang_guan_bms_soc"),
        ("forecast", "sensor.solcast_pv_forecast_forecast_today"),
    ]

    static var template: String {
        entities.map { "{{ states('\($0.1)') }}" }.joined(separator: "|")
    }
}

// MARK: - 错误

enum HAError: LocalizedError {
    case notConfigured
    case badURL
    case unauthorized
    case http(Int)
    case badBody

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有配置 HA 地址和令牌"
        case .badURL:        return "HA 地址格式不对（IPv6 要带方括号）"
        case .unauthorized:  return "令牌无效或已过期（401）"
        case .http(let c):   return "HA 返回 HTTP \(c)"
        case .badBody:       return "返回内容无法解析"
        }
    }
}

// MARK: - 数据

struct SolarData: Equatable {
    var pv: Double?        // W
    var daily: Double?     // kWh
    var total: Double?     // kWh
    var load: Double?      // W
    var soc: Double?       // %
    var forecast: Double?  // kWh
    var updatedAt: Date

    static func parse(_ text: String) -> SolarData {
        let parts = text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func num(_ i: Int) -> Double? {
            guard i < parts.count else { return nil }
            let raw = parts[i]
            guard raw != "unknown", raw != "unavailable", raw != "None", !raw.isEmpty else { return nil }
            return Double(raw)
        }
        return SolarData(
            pv: num(0), daily: num(1), total: num(2),
            load: num(3), soc: num(4), forecast: num(5),
            updatedAt: Date()
        )
    }
}

// MARK: - 客户端

struct HAClient {
    let baseURL: String
    let token: String

    func fetchSolar() async throws -> SolarData {
        guard !baseURL.isEmpty, !token.isEmpty else { throw HAError.notConfigured }

        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed + "/api/template") else { throw HAError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["template": SolarConfig.template])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw HAError.badBody }
        if http.statusCode == 401 { throw HAError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw HAError.http(http.statusCode) }

        // /api/template 返回 JSON 字符串；个别版本返回裸文本，两种都接受
        let text: String
        if let decoded = try? JSONDecoder().decode(String.self, from: data) {
            text = decoded
        } else if let raw = String(data: data, encoding: .utf8) {
            text = raw
        } else {
            throw HAError.badBody
        }
        return SolarData.parse(text)
    }
}
