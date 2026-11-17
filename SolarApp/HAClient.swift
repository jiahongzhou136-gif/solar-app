import Foundation

// MARK: - 实体配置

enum SolarConfig {
    /// 示例地址；首次启动在 App 设置页填自己的 HA 地址
    static let defaultBaseURL = "http://192.168.1.100:8123"
    static let defaultPanelURL = "http://192.168.1.100:8123/solar-board/solar"

    static let prefix = "sensor.guang_fu_ben_di_wang_guan_"

    /// 主界面一次取回（顺序即解析下标，勿随意调整）
    static let mainEntities: [String] = [
        prefix + "pv1_power",                          // 0
        prefix + "pv1_voltage",                        // 1
        prefix + "pv1_current",                        // 2
        prefix + "pv_total_power",                     // 3
        prefix + "load_power",                         // 4
        prefix + "bms_soc",                            // 5
        prefix + "battery_charge_power",               // 6
        prefix + "battery_discharge_power",            // 7
        prefix + "grid_power_raw",                     // 8
        prefix + "daily_battery_charge_energy",        // 9
        prefix + "daily_battery_discharge_energy",     // 10
        prefix + "daily_pv_energy",                    // 11
        prefix + "total_pv_energy",                    // 12
        "sensor.solcast_pv_forecast_forecast_today",             // 13
        "sensor.solcast_pv_forecast_forecast_remaining_today",   // 14
        "sensor.solcast_pv_forecast_forecast_tomorrow",          // 15
        "weather.forecast_wo_de_jia",                            // 16
        prefix + "inverter_temperature",               // 17
        prefix + "inverter_status_raw",                // 18
        prefix + "inverter_warning_code_raw",          // 19
    ]

    static func template(_ ids: [String]) -> String {
        ids.map { "{{ states('\($0)') }}" }.joined(separator: "|")
    }
}

// MARK: - 错误

enum HAError: LocalizedError {
    case notConfigured
    case badURL
    case unauthorized
    case http(Int)
    case badBody
    case emptyResponse
    case unexpectedBody(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有配置 HA 地址和令牌"
        case .badURL:        return "HA 地址格式不对（IPv6 要带方括号）"
        case .unauthorized:  return "令牌无效或已过期（401）"
        case .http(let c):   return "HA 返回 HTTP \(c)"
        case .badBody:       return "返回内容无法解析"
        case .emptyResponse: return "HA 返回了空内容，检查地址是否正确"
        case .unexpectedBody(let s): return "返回内容异常：\(s)"
        }
    }
}

// MARK: - 天气

enum WeatherKind: String {
    case sunny, cloudy, rain, night

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

    static func from(_ raw: String) -> WeatherKind {
        let s = raw.lowercased()
        if s.contains("night") {
            return (s.contains("rain") || s.contains("pouring") || s.contains("lightning")) ? .rain : .night
        }
        if s.contains("rain") || s.contains("pouring") || s.contains("lightning") || s.contains("snow") {
            return .rain
        }
        if s.contains("sunny") || s.contains("clear") {
            return .sunny
        }
        return .cloudy
    }
}

// MARK: - 设备类型

enum DeviceKind: String, CaseIterable, Identifiable, Hashable {
    case pv1, inverter, battery, grid, load

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pv1:      return "PV1"
        case .inverter: return "逆变器"
        case .battery:  return "储能电池"
        case .grid:     return "市电"
        case .load:     return "住宅负载"
        }
    }

    var icon: String {
        switch self {
        case .pv1:      return "sun.max.fill"
        case .inverter: return "bolt.horizontal.circle.fill"
        case .battery:  return "battery.75percent"
        case .grid:     return "powerplug.fill"
        case .load:     return "house.fill"
        }
    }

    var kicker: String {
        switch self {
        case .pv1:      return "PV ARRAY · LIVE"
        case .inverter: return "INVERTER · LIVE"
        case .battery:  return "ENERGY STORAGE · LIVE"
        case .grid:     return "GRID · LIVE"
        case .load:     return "HOME LOAD · LIVE"
        }
    }

    var desc: String {
        switch self {
        case .pv1:      return "光伏组串实时输出与发电累计"
        case .inverter: return "逆变器输出、温度与运行状态"
        case .battery:  return "实时运行与电池管理状态"
        case .grid:     return "市电功率与流向"
        case .load:     return "住宅当前用电与累计用电"
        }
    }

    struct Field {
        let label: String
        let entity: String
        let unit: String
        let digits: Int
    }

    var fields: [Field] {
        let p = SolarConfig.prefix
        switch self {
        case .pv1:
            return [
                .init(label: "实时功率", entity: p + "pv1_power", unit: "W", digits: 0),
                .init(label: "电压", entity: p + "pv1_voltage", unit: "V", digits: 1),
                .init(label: "电流", entity: p + "pv1_current", unit: "A", digits: 2),
                .init(label: "今日发电", entity: p + "daily_pv_energy", unit: "kWh", digits: 2),
                .init(label: "累计发电", entity: p + "total_pv_energy", unit: "kWh", digits: 1),
            ]
        case .inverter:
            return [
                .init(label: "输出功率", entity: p + "pv_total_power", unit: "W", digits: 0),
                .init(label: "温度", entity: p + "inverter_temperature", unit: "°C", digits: 1),
                .init(label: "Bus1 电压", entity: p + "bus1_voltage", unit: "V", digits: 1),
                .init(label: "运行状态", entity: p + "inverter_status_raw", unit: "", digits: 0),
                .init(label: "告警码", entity: p + "inverter_warning_code_raw", unit: "", digits: 0),
                .init(label: "累计运行", entity: p + "inverter_runtime_raw", unit: "h", digits: 0),
            ]
        case .battery:
            return [
                .init(label: "SOC", entity: p + "bms_soc", unit: "%", digits: 0),
                .init(label: "电压", entity: p + "battery_voltage", unit: "V", digits: 2),
                .init(label: "电流", entity: p + "battery_current", unit: "A", digits: 2),
                .init(label: "温度", entity: p + "battery_temperature", unit: "°C", digits: 1),
                .init(label: "充电功率", entity: p + "battery_charge_power", unit: "W", digits: 0),
                .init(label: "放电功率", entity: p + "battery_discharge_power", unit: "W", digits: 0),
                .init(label: "剩余容量", entity: p + "bms_remaining_capacity", unit: "Ah", digits: 1),
                .init(label: "额定容量", entity: p + "bms_nominal_capacity", unit: "Ah", digits: 0),
                .init(label: "循环次数", entity: p + "bms_cycle_count", unit: "次", digits: 0),
                .init(label: "最高单体", entity: p + "bms_max_cell_voltage", unit: "V", digits: 3),
                .init(label: "最低单体", entity: p + "bms_min_cell_voltage", unit: "V", digits: 3),
                .init(label: "单体压差", entity: p + "bms_cell_delta", unit: "V", digits: 3),
            ]
        case .grid:
            return [
                .init(label: "实时功率", entity: p + "grid_power_raw", unit: "W", digits: 0),
            ]
        case .load:
            return [
                .init(label: "实时功率", entity: p + "load_power", unit: "W", digits: 0),
                .init(label: "今日用电", entity: p + "daily_load_energy", unit: "kWh", digits: 2),
                .init(label: "累计用电", entity: p + "total_load_energy", unit: "kWh", digits: 1),
            ]
        }
    }

    var cellEntities: [String] {
        guard self == .battery else { return [] }
        return (1...16).map {
            String(format: "sensor.guang_fu_ben_di_wang_guan_bms_cell_voltage_%02d", $0)
        }
    }
}

// MARK: - 主数据

struct SolarData: Equatable {
    var pv1: Double?
    var pv1Voltage: Double?
    var pv1Current: Double?
    var pvTotal: Double?
    var load: Double?
    var soc: Double?
    var charge: Double?
    var discharge: Double?
    var grid: Double?
    var dailyCharge: Double?
    var dailyDischarge: Double?
    var dailyPv: Double?
    var totalPv: Double?
    var forecastToday: Double?
    var forecastRemaining: Double?
    var forecastTomorrow: Double?
    var weatherRaw: String
    var inverterTemp: Double?
    var inverterStatus: String
    var warningCode: String
    var rawPreview: String
    var updatedAt: Date

    var weather: WeatherKind { WeatherKind.from(weatherRaw) }

    /// 电池净功率：正=充电，负=放电
    var batteryPower: Double? {
        guard charge != nil || discharge != nil else { return nil }
        return (charge ?? 0) - (discharge ?? 0)
    }

    var isEmptyReading: Bool {
        pv1 == nil && load == nil && soc == nil && dailyPv == nil && forecastToday == nil
    }

    var forecastProgress: Double? {
        guard let f = forecastToday, f > 1, let d = dailyPv else { return nil }
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

        let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text

        return SolarData(
            pv1: num(0),
            pv1Voltage: num(1),
            pv1Current: num(2),
            pvTotal: num(3),
            load: num(4),
            soc: num(5),
            charge: num(6),
            discharge: num(7),
            grid: num(8),
            dailyCharge: num(9),
            dailyDischarge: num(10),
            dailyPv: num(11),
            totalPv: num(12),
            forecastToday: num(13),
            forecastRemaining: num(14),
            forecastTomorrow: num(15),
            weatherRaw: str(16),
            inverterTemp: num(17),
            inverterStatus: str(18),
            warningCode: str(19),
            rawPreview: preview,
            updatedAt: Date()
        )
    }

    static let empty = SolarData(
        pv1: nil, pv1Voltage: nil, pv1Current: nil, pvTotal: nil, load: nil,
        soc: nil, charge: nil, discharge: nil, grid: nil,
        dailyCharge: nil, dailyDischarge: nil, dailyPv: nil, totalPv: nil,
        forecastToday: nil, forecastRemaining: nil, forecastTomorrow: nil,
        weatherRaw: "", inverterTemp: nil, inverterStatus: "", warningCode: "",
        rawPreview: "", updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - 详情数据

struct DeviceDetail: Equatable {
    var fields: [(String, String)] = []
    var cells: [Double] = []
    var note: String?

    static func == (lhs: DeviceDetail, rhs: DeviceDetail) -> Bool {
        lhs.fields.map { $0.0 + $0.1 } == rhs.fields.map { $0.0 + $0.1 }
            && lhs.cells == rhs.cells
    }
}

// MARK: - 客户端

struct HAClient {
    let baseURL: String
    let token: String

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func postTemplate(_ ids: [String]) async throws -> String {
        guard !baseURL.isEmpty, !token.isEmpty else { throw HAError.notConfigured }
        let base = HAClient.normalize(baseURL)
        guard !base.isEmpty, let url = URL(string: base + "/api/template") else { throw HAError.badURL }

        let body = try JSONSerialization.data(
            withJSONObject: ["template": SolarConfig.template(ids)]
        )
        let headers = [
            "Authorization": "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "SolarApp/1.0",
        ]

        // 走 Network.framework，避开 ATS 对明文 HTTP 的拦截
        let (status, data) = try await RawHTTP.post(url: url, headers: headers, body: body)

        if status == 401 { throw HAError.unauthorized }
        guard (200..<300).contains(status) else { throw HAError.http(status) }

        let text: String
        if let decoded = try? JSONDecoder().decode(String.self, from: data) {
            text = decoded
        } else if let raw = String(data: data, encoding: .utf8) {
            text = raw
        } else {
            throw HAError.badBody
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw HAError.emptyResponse }
        return trimmed
    }

    func fetchSolar() async throws -> SolarData {
        let text = try await postTemplate(SolarConfig.mainEntities)
        let parsed = SolarData.parse(text)
        if parsed.isEmptyReading {
            throw HAError.unexpectedBody(String(text.prefix(100)))
        }
        return parsed
    }

    func fetchDetail(_ kind: DeviceKind) async throws -> DeviceDetail {
        let ids = kind.fields.map(\.entity) + kind.cellEntities
        let text = try await postTemplate(ids)
        let parts = text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        func rawValue(_ i: Int) -> String {
            guard i < parts.count else { return "" }
            let v = parts[i]
            return (v == "unknown" || v == "unavailable" || v == "None") ? "" : v
        }
        func display(_ raw: String, unit: String, digits: Int) -> String {
            guard let d = Double(raw) else { return raw.isEmpty ? "--" : raw }
            let number = String(format: "%.\(digits)f", d)
            return unit.isEmpty ? number : number + " " + unit
        }

        var fields: [(String, String)] = []
        for (i, f) in kind.fields.enumerated() {
            fields.append((f.label, display(rawValue(i), unit: f.unit, digits: f.digits)))
        }

        var cells: [Double] = []
        let start = kind.fields.count
        for i in start..<(start + kind.cellEntities.count) where i < parts.count {
            if let d = Double(parts[i]) { cells.append(d) }
        }

        let note = kind == .battery
            ? "折算剩余电量 = BMS 实时总压 × BMS 剩余 Ah ÷ 1000，是参考值，不等同实验室可释放电量。"
            : nil

        return DeviceDetail(fields: fields, cells: cells, note: note)
    }
}
