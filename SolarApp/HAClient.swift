import Foundation

// MARK: - 实体配置

enum SolarConfig {
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
        "sun.sun",                                     // 20（夜间判定，与面板同源）
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
        /// 值为 on/off 这类文本时的映射
        var textMap: [String: String] = [:]
    }

    struct FieldGroup {
        let title: String
        let fields: [Field]
    }

    /// 与 HA 面板 `_detailDialog` / `_batteryDialog` 的字段顺序保持一致
    var groups: [FieldGroup] {
        let p = SolarConfig.prefix
        switch self {
        case .pv1:
            return [FieldGroup(title: "实时运行", fields: [
                .init(label: "PV1 功率", entity: p + "pv1_power", unit: "W", digits: 0),
                .init(label: "PV1 电压", entity: p + "pv1_voltage", unit: "V", digits: 1),
                .init(label: "PV1 电流", entity: p + "pv1_current", unit: "A", digits: 2),
                .init(label: "PV2", entity: p + "pv2_power", unit: "W", digits: 0),
                .init(label: "今日发电", entity: p + "daily_pv_energy", unit: "kWh", digits: 2),
                .init(label: "总发电", entity: p + "total_pv_energy", unit: "kWh", digits: 2),
            ])]

        case .inverter:
            return [FieldGroup(title: "实时运行", fields: [
                .init(label: "输出 / 负载", entity: p + "pv_total_power", unit: "W", digits: 0),
                .init(label: "逆变器温度", entity: p + "inverter_temperature", unit: "°C", digits: 1),
                .init(label: "Bus1 内部电压", entity: p + "bus1_voltage", unit: "V", digits: 1),
                .init(label: "故障", entity: p + "inverter_fault_code_raw", unit: "", digits: 0),
                .init(label: "主告警", entity: p + "inverter_warning_code_raw", unit: "", digits: 0),
            ])]

        case .grid:
            return [FieldGroup(title: "实时运行", fields: [
                .init(label: "当前购电", entity: p + "grid_import_power", unit: "W", digits: 0),
                .init(label: "当前馈网", entity: p + "grid_export_power", unit: "W", digits: 0),
                .init(label: "实时功率（原始）", entity: p + "grid_power_raw", unit: "W", digits: 0),
                .init(label: "今日购电", entity: p + "daily_grid_import_energy", unit: "kWh", digits: 2),
                .init(label: "今日馈网", entity: p + "daily_grid_export_energy", unit: "kWh", digits: 2),
            ])]

        case .load:
            return [FieldGroup(title: "实时运行", fields: [
                .init(label: "当前负载", entity: p + "load_power", unit: "W", digits: 0),
                .init(label: "今日用电", entity: p + "daily_load_energy", unit: "kWh", digits: 2),
            ])]

        case .battery:
            return [
                FieldGroup(title: "逆变器数据", fields: [
                    .init(label: "SOC", entity: p + "bms_soc", unit: "%", digits: 0),
                    .init(label: "充电功率", entity: p + "battery_charge_power", unit: "W", digits: 0),
                    .init(label: "放电功率", entity: p + "battery_discharge_power", unit: "W", digits: 0),
                    .init(label: "电压", entity: p + "battery_voltage", unit: "V", digits: 2),
                    .init(label: "电流", entity: p + "battery_current", unit: "A", digits: 2),
                    .init(label: "温度", entity: p + "battery_temperature", unit: "°C", digits: 1),
                    .init(label: "BMS 剩余容量", entity: p + "bms_remaining_capacity", unit: "Ah", digits: 2),
                ]),
                FieldGroup(title: "BMS 数据", fields: [
                    .init(label: "SOC", entity: p + "bms_soc", unit: "%", digits: 0),
                    .init(label: "总压", entity: p + "bms_pack_voltage", unit: "V", digits: 2),
                    .init(label: "电流", entity: p + "bms_current", unit: "A", digits: 2),
                    .init(label: "温度", entity: p + "bms_temperature_1", unit: "°C", digits: 1),
                    .init(label: "剩余容量", entity: p + "bms_remaining_capacity", unit: "Ah", digits: 1),
                    .init(label: "标称容量", entity: p + "bms_nominal_capacity", unit: "Ah", digits: 1),
                    .init(label: "循环次数", entity: p + "bms_cycle_count", unit: "次", digits: 0),
                    .init(label: "最高单体", entity: p + "bms_max_cell_voltage", unit: "V", digits: 3),
                    .init(label: "最低单体", entity: p + "bms_min_cell_voltage", unit: "V", digits: 3),
                    .init(label: "压差", entity: p + "bms_cell_delta", unit: "V", digits: 3),
                    .init(label: "均衡", entity: "binary_sensor.guang_fu_ben_di_wang_guan_bms_balancing",
                          unit: "", digits: 0,
                          textMap: ["on": "均衡中", "off": "未均衡"]),
                    .init(label: "告警", entity: p + "bms_errors", unit: "", digits: 0),
                ]),
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
    var sunState: String
    var rawPreview: String
    var updatedAt: Date

    var weather: WeatherKind { WeatherKind.from(weatherRaw) }

    /// 与 HA 面板一致：优先 sun.sun，取不到时用本地时间兜底
    var isNight: Bool {
        let s = sunState.lowercased()
        if s == "below_horizon" { return true }
        if s == "above_horizon" { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 6 || hour >= 18
    }

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
            sunState: str(20),
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
        sunState: "",
        rawPreview: "", updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - 详情数据

struct DetailSection: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var fields: [(String, String)]

    static func == (lhs: DetailSection, rhs: DetailSection) -> Bool {
        lhs.title == rhs.title
            && lhs.fields.map { $0.0 + $0.1 } == rhs.fields.map { $0.0 + $0.1 }
    }
}

struct DeviceDetail: Equatable {
    var sections: [DetailSection] = []
    var cells: [Double] = []
    var note: String?

    static func == (lhs: DeviceDetail, rhs: DeviceDetail) -> Bool {
        lhs.sections == rhs.sections && lhs.cells == rhs.cells
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
        let groups = kind.groups
        let allFields = groups.flatMap { $0.fields }
        let ids = allFields.map(\.entity) + kind.cellEntities
        let text = try await postTemplate(ids)

        let parts = text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        func rawValue(_ i: Int) -> String {
            guard i < parts.count else { return "" }
            let v = parts[i]
            return (v == "unknown" || v == "unavailable" || v == "None") ? "" : v
        }
        func display(_ raw: String, field: DeviceKind.Field) -> String {
            if let mapped = field.textMap[raw] { return mapped }
            guard let d = Double(raw) else { return raw.isEmpty ? "--" : raw }
            let number = String(format: "%.\(field.digits)f", d)
            return field.unit.isEmpty ? number : number + " " + field.unit
        }

        var sections: [DetailSection] = []
        var cursor = 0
        var rawByLabel: [String: Double] = [:]

        for group in groups {
            var rows: [(String, String)] = []
            for field in group.fields {
                let raw = rawValue(cursor)
                if let d = Double(raw) { rawByLabel[field.label] = d }
                rows.append((field.label, display(raw, field: field)))
                cursor += 1
            }
            sections.append(DetailSection(title: group.title, fields: rows))
        }

        // 折算剩余电量：总压 × 剩余 Ah ÷ 1000（与 HA 面板同算法）
        if kind == .battery,
           let voltage = rawByLabel["电压"] ?? rawByLabel["总压"],
           let ah = rawByLabel["BMS 剩余容量"] ?? rawByLabel["剩余容量"] {
            let kwh = voltage * ah / 1000.0
            if let idx = sections.firstIndex(where: { $0.title == "逆变器数据" }) {
                sections[idx].fields.append(("折算剩余电量", String(format: "%.2f kWh", kwh)))
            }
        }

        var cells: [Double] = []
        let start = allFields.count
        for i in start..<(start + kind.cellEntities.count) where i < parts.count {
            if let d = Double(parts[i]) { cells.append(d) }
        }

        let note: String?
        switch kind {
        case .battery:
            note = "折算剩余电量 = BMS 实时总压 × BMS 剩余 Ah ÷ 1000，是参考值，不等同实验室可释放电量。"
        case .grid:
            note = "当前功率只显示网关真实发布值；正值取电，负值馈电，零值正常，不用差值猜测。"
        case .inverter:
            note = "码值与说明取自说明书「7.1 报错代码」；故障与告警是两张独立码表。"
        default:
            note = nil
        }

        return DeviceDetail(sections: sections, cells: cells, note: note)
    }
}
