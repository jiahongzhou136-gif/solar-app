import Foundation

// MARK: - 配置

enum SolarConfig {
    /// 示例地址；首次启动在 App 设置页填自己的 HA 地址
    static let defaultBaseURL = "http://192.168.1.100:8123"
    static let defaultPanelURL = "http://192.168.1.100:8123/solar-board/solar"

    /// 一次模板请求取回全部数值，避免十几次 HTTP 往返
    static let entities: [(String, String)] = [
        ("pv1",        "sensor.guang_fu_ben_di_wang_guan_pv1_power"),
        ("pv2",        "sensor.guang_fu_ben_di_wang_guan_pv2_power"),
        ("load",       "sensor.guang_fu_ben_di_wang_guan_load_power"),
        ("soc",        "sensor.guang_fu_ben_di_wang_guan_bms_soc"),
        ("charge",     "sensor.guang_fu_ben_di_wang_guan_battery_charge_power"),
        ("discharge",  "sensor.guang_fu_ben_di_wang_guan_battery_discharge_power"),
        ("grid",       "sensor.guang_fu_ben_di_wang_guan_grid_power_raw"),
        ("daily",      "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy"),
        ("total",      "sensor.guang_fu_ben_di_wang_guan_total_pv_energy"),
        ("fcToday",    "sensor.solcast_pv_forecast_forecast_today"),
        ("fcRemain",   "sensor.solcast_pv_forecast_forecast_remaining_today"),
        ("fcTomorrow", "sensor.solcast_pv_forecast_forecast_tomorrow"),
        ("weather",    "weather.forecast_wo_de_jia"),
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

// MARK: - 天气

enum WeatherKind: String {
    case sunny
    case cloudy
    case rain
    case night

    var imageName: String {
        switch self {
        case .sunny:  return "WeatherSunny"
        case .cloudy: return "WeatherCloudy"
        case .rain:   return "WeatherRain"
        case .night:  return "WeatherNight"
        }
    }

    var symbol: String {
        switch self {
        case .sunny:  return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain:   return "cloud.rain.fill"
        case .night:  return "moon.stars.fill"
        }
    }

    var label: String {
        switch self {
        case .sunny:  return "晴"
        case .cloudy: return "多云"
        case .rain:   return "有雨"
        case .night:  return "夜间"
        }
    }

    /// HA 天气实体 state → 视觉分类
    static func from(_ raw: String) -> WeatherKind {
        let s = raw.lowercased()
        if s.contains("night") {
            return s.contains("rain") || s.contains("pouring") || s.contains("lightning") ? .rain : .night
        }
        if s.contains("rain") || s.contains("pouring") || s.contains("lightning") || s.contains("snow") {
            return .rain
        }
        if s.contains("sunny") || s.contains("clear") {
            return .sunny
        }
        if s.contains("cloud") || s.contains("fog") || s.contains("wind") || s.contains("hail") {
            return .cloudy
        }
        return .cloudy
    }
}

// MARK: - 数据

struct SolarData: Equatable {
    var pv1: Double?          // W
    var pv2: Double?          // W（未接入时为 nil）
    var load: Double?         // W
    var soc: Double?          // %
    var charge: Double?       // W
    var discharge: Double?    // W
    var grid: Double?         // W
    var daily: Double?        // kWh
    var total: Double?        // kWh
    var forecastToday: Double?
    var forecastRemaining: Double?
    var forecastTomorrow: Double?
    var weatherRaw: String
    var updatedAt: Date

    var weather: WeatherKind { WeatherKind.from(weatherRaw) }

    /// 电池净功率：正=充电，负=放电
    var batteryPower: Double? {
        guard charge != nil || discharge != nil else { return nil }
        return (charge ?? 0) - (discharge ?? 0)
    }

    var isBatteryCharging: Bool { (batteryPower ?? 0) > 20 }
    var isBatteryDischarging: Bool { (batteryPower ?? 0) < -20 }

    /// 今日预测完成度 0...1
    var forecastProgress: Double? {
        guard let f = forecastToday, f > 1, let d = daily else { return nil }
        return min(max(d / f, 0), 1)
    }

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
        func str(_ i: Int) -> String {
            guard i < parts.count else { return "" }
            let raw = parts[i]
            return (raw == "unknown" || raw == "unavailable") ? "" : raw
        }

        return SolarData(
            pv1: num(0),
            pv2: num(1),
            load: num(2),
            soc: num(3),
            charge: num(4),
            discharge: num(5),
            grid: num(6),
            daily: num(7),
            total: num(8),
            forecastToday: num(9),
            forecastRemaining: num(10),
            forecastTomorrow: num(11),
            weatherRaw: str(12),
            updatedAt: Date()
        )
    }

    static let empty = SolarData(
        pv1: nil, pv2: nil, load: nil, soc: nil, charge: nil, discharge: nil,
        grid: nil, daily: nil, total: nil, forecastToday: nil,
        forecastRemaining: nil, forecastTomorrow: nil, weatherRaw: "",
        updatedAt: Date(timeIntervalSince1970: 0)
    )
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
