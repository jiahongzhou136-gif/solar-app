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
        // 21：未来数小时天气状况，用于「预计多久有雨」
        "raw:" + SolarConfig.forecastConditionsRaw,
    ]

    /// 取天气实体的逐时预报状况（缺失时返回空串，前端自动隐藏该文案）
    static let forecastConditionsRaw =
        "{% set f = state_attr('weather.forecast_wo_de_jia','forecast') %}{{ (f[:4] | map(attribute='condition') | join(',')) if f else '' }}"

    static func template(_ ids: [String]) -> String {
        ids.map { id in
            id.hasPrefix("raw:")
                ? "{{ \(id.dropFirst(4)) }}"
                : "{{ states('\(id)') }}"
        }.joined(separator: "|")
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

    /// 统一把底层错误转成中文可读文案，绝不把 NSURLErrorDomain 之类的原始串抛给用户
    static func describe(_ error: Error) -> String {
        if let e = error as? HAError {
            return e.errorDescription ?? "读取失败"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:              return "连接超时，HA 没有响应"
            case NSURLErrorCannotConnectToHost:   return "无法连接到 HA，检查地址与端口"
            case NSURLErrorCannotFindHost:        return "找不到主机，域名解析失败"
            case NSURLErrorNetworkConnectionLost: return "网络中断，正在重连"
            case NSURLErrorNotConnectedToInternet: return "设备未联网"
            case NSURLErrorCancelled:             return "请求已取消"
            default:                              return "网络请求失败（\(ns.code)）"
            }
        }
        if ns.domain.contains("Network") || ns.domain.contains("NWError") {
            return "网络连接失败，检查 HA 地址与局域网"
        }
        return "读取失败"
    }
}

// MARK: - 数值合理性

/// 网关偶发返回 uint32 越界值（例如电池充电功率 429,496,544 W），
/// 这里按物理量程做兜底，超范围一律视为无效值（显示 --），与面板 POWER_LIMITS 同思路。
enum Sanity {
    static func check(_ value: Double, unit: String) -> Double? {
        guard value.isFinite else { return nil }
        switch unit {
        case "W":            return abs(value) <= 30_000 ? value : nil
        case "V":            return (0...1_000).contains(value) ? value : nil
        case "A":            return abs(value) <= 500 ? value : nil
        case "%":            return (0...100).contains(value) ? value : nil
        case "°C":           return (-50...150).contains(value) ? value : nil
        case "kWh":          return (0...10_000_000).contains(value) ? value : nil
        case "Ah":           return (0...100_000).contains(value) ? value : nil
        case "次":           return (0...1_000_000).contains(value) ? value : nil
        default:             return abs(value) <= 10_000_000 ? value : nil
        }
    }
}

// MARK: - 天气

/// 只描述天气本身；昼夜是独立维度（SolarData.isNight），不参与天气判定
enum WeatherKind: String {
    case sunny, cloudy, rain

    var imageName: String {
        switch self {
        case .sunny:  return "WeatherSunny"
        case .cloudy: return "WeatherCloudy"
        case .rain:   return "WeatherRain"
        }
    }

    /// 白天符号
    var symbol: String {
        switch self {
        case .sunny:  return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain:   return "cloud.rain.fill"
        }
    }

    /// 夜间符号：天气不变，只换图标形态
    var nightSymbol: String {
        switch self {
        case .sunny:  return "moon.stars.fill"
        case .cloudy: return "cloud.moon.fill"
        case .rain:   return "cloud.moon.rain.fill"
        }
    }

    var label: String {
        switch self {
        case .sunny:  return "晴"
        case .cloudy: return "多云"
        case .rain:   return "有雨"
        }
    }

    static func from(_ raw: String) -> WeatherKind {
        let s = raw.lowercased()
        if s.contains("rain") || s.contains("pouring") || s.contains("lightning")
            || s.contains("snow") || s.contains("hail") {
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

    /// 与 HA 面板完全一致的图标
    var icon: HAIcon {
        switch self {
        case .pv1:      return .solar
        case .inverter: return .inverter
        case .battery:  return .battery
        case .grid:     return .grid
        case .load:     return .home
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
        /// 实体在现场不存在时的静态文案（例如 PV2「未接入」）
        var missingText: String? = nil
        /// 主实体缺失或不可用时，改从该实体派生（与 HA 面板 fallback 同源）
        var deriveFrom: String? = nil
        var derive: Derive = .none
        /// 数值为 0 时改显示的文字（例如告警码「无」）
        var zeroText: String? = nil

        enum Derive {
            case none
            /// 原样取备用实体的值
            case fallback
            /// 正数部分（购电）
            case importPower
            /// 负数部分的绝对值（馈网）
            case exportPower
        }
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
                .init(label: "PV2", entity: p + "pv2_power", unit: "W", digits: 0, missingText: "未接入"),
                .init(label: "今日发电", entity: p + "daily_pv_energy", unit: "kWh", digits: 2),
                .init(label: "总发电", entity: p + "total_pv_energy", unit: "kWh", digits: 2),
            ])]

        case .inverter:
            return [FieldGroup(title: "实时运行", fields: [
                // 与面板 _inverterPowerKey() 一致：有 inverter_output_power 用它，否则退回 load_power
                .init(label: "输出 / 负载", entity: p + "inverter_output_power", unit: "W", digits: 0,
                      deriveFrom: p + "load_power", derive: .fallback),
                .init(label: "逆变器温度", entity: p + "inverter_temperature", unit: "°C", digits: 1),
                .init(label: "Bus1 内部电压", entity: p + "bus1_voltage", unit: "V", digits: 1),
                // 现场只有一个码寄存器，故障通道未接线；面板同样不显示该行
                .init(label: "主告警", entity: p + "inverter_warning_code_raw", unit: "", digits: 0,
                      zeroText: "无"),
            ])]

        case .grid:
            return [FieldGroup(title: "实时运行", fields: [
                // 现场无 grid_import_power / grid_export_power，与面板一致从 grid_power_raw 拆分
                .init(label: "当前购电", entity: p + "grid_import_power", unit: "W", digits: 0,
                      deriveFrom: p + "grid_power_raw", derive: .importPower),
                .init(label: "当前馈网", entity: p + "grid_export_power", unit: "W", digits: 0,
                      deriveFrom: p + "grid_power_raw", derive: .exportPower),
                .init(label: "实时功率（原始）", entity: p + "grid_power_raw", unit: "W", digits: 0),
                .init(label: "今日购电", entity: p + "daily_grid_import_energy", unit: "kWh", digits: 2),
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
                    .init(label: "最高单体", entity: p + "bms_cell_max_voltage", unit: "V", digits: 3),
                    .init(label: "最低单体", entity: p + "bms_cell_min_voltage", unit: "V", digits: 3),
                    .init(label: "压差", entity: p + "bms_cell_delta_voltage", unit: "V", digits: 3),
                    .init(label: "均衡", entity: "binary_sensor.guang_fu_ben_di_wang_guan_bms_balancing",
                          unit: "", digits: 0,
                          textMap: ["on": "均衡中", "off": "未均衡"]),
                    .init(label: "告警", entity: p + "bms_errors", unit: "", digits: 0, missingText: "无告警"),
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
    var forecastConditions: String
    var rawPreview: String
    var updatedAt: Date

    var weather: WeatherKind { WeatherKind.from(weatherRaw) }

    /// 与面板一致的降雨预报文案；取不到逐时预报时返回 nil，前端不显示
    var rainSoonText: String? {
        let items = forecastConditions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }

        func isWet(_ c: String) -> Bool {
            c.contains("rain") || c.contains("pouring") || c.contains("lightning")
                || c.contains("snow") || c.contains("hail") || c.contains("shower")
        }

        if let idx = items.firstIndex(where: isWet) {
            return idx == 0 ? "即将有雨" : "约 \(idx + 1) 小时后有雨"
        }
        return "未来 \(min(items.count, 3)) 小时无雨"
    }

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
        // 按物理量程过滤越界值
        func meter(_ i: Int, _ unit: String) -> Double? {
            num(i).flatMap { Sanity.check($0, unit: unit) }
        }

        let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text

        return SolarData(
            pv1: meter(0, "W"),
            pv1Voltage: meter(1, "V"),
            pv1Current: meter(2, "A"),
            pvTotal: meter(3, "W"),
            load: meter(4, "W"),
            soc: meter(5, "%"),
            charge: meter(6, "W"),
            discharge: meter(7, "W"),
            grid: meter(8, "W"),
            dailyCharge: meter(9, "kWh"),
            dailyDischarge: meter(10, "kWh"),
            dailyPv: meter(11, "kWh"),
            totalPv: meter(12, "kWh"),
            forecastToday: meter(13, "kWh"),
            forecastRemaining: meter(14, "kWh"),
            forecastTomorrow: meter(15, "kWh"),
            weatherRaw: str(16),
            inverterTemp: meter(17, "°C"),
            inverterStatus: str(18),
            warningCode: str(19),
            sunState: str(20),
            forecastConditions: str(21),
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
        sunState: "", forecastConditions: "",
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

        // 主实体 + 派生来源，去重后一次请求；取值按实体名回查，不依赖下标
        var ordered: [String] = []
        for field in allFields {
            if !ordered.contains(field.entity) { ordered.append(field.entity) }
            if let src = field.deriveFrom, !ordered.contains(src) { ordered.append(src) }
        }
        for entity in kind.cellEntities where !ordered.contains(entity) { ordered.append(entity) }

        let text = try await postTemplate(ordered)
        let parts = text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        func rawValue(_ entity: String) -> String {
            guard let i = ordered.firstIndex(of: entity), i < parts.count else { return "" }
            let v = parts[i]
            return (v == "unknown" || v == "unavailable" || v == "None") ? "" : v
        }
        func number(_ entity: String) -> Double? { Double(rawValue(entity)) }
        func display(_ value: Double, _ field: DeviceKind.Field) -> String {
            let s = String(format: "%.\(field.digits)f", value)
            return field.unit.isEmpty ? s : s + " " + field.unit
        }

        var sections: [DetailSection] = []

        for group in groups {
            var rows: [(String, String)] = []
            for field in group.fields {
                // 1) 先读主实体；2) 缺失时按规则从备用实体派生（两者都过量程校验）
                var value = number(field.entity).flatMap { Sanity.check($0, unit: field.unit) }
                if value == nil, let src = field.deriveFrom {
                    let base = number(src).flatMap { Sanity.check($0, unit: "W") }
                    if let base {
                        switch field.derive {
                        case .none:        break
                        case .fallback:    value = base
                        case .importPower: value = max(base, 0)
                        case .exportPower: value = max(-base, 0)
                        }
                    }
                }

                let shown: String
                if let v = value {
                    let mapped = field.textMap[rawValue(field.entity)] ?? ""
                    if let zero = field.zeroText, abs(v) < 0.0001 {
                        shown = zero
                    } else if !mapped.isEmpty {
                        shown = mapped
                    } else {
                        shown = display(v, field)
                    }
                } else {
                    let raw = rawValue(field.entity)
                    let mapped = field.textMap[raw] ?? ""
                    if !mapped.isEmpty {
                        shown = mapped
                    } else if let missing = field.missingText {
                        shown = missing
                    } else {
                        shown = raw.isEmpty ? "--" : raw
                    }
                }
                rows.append((field.label, shown))
            }
            sections.append(DetailSection(title: group.title, fields: rows))
        }

        // 折算剩余电量：bms_pack_voltage × bms_remaining_capacity ÷ 1000（与面板 _remainingEnergyKwh 同源）
        let prefix = SolarConfig.prefix
        if kind == .battery,
           let voltage = number(prefix + "bms_pack_voltage"),
           let ampHours = number(prefix + "bms_remaining_capacity"),
           let idx = sections.firstIndex(where: { $0.title == "逆变器数据" }) {
            sections[idx].fields.append(
                ("折算剩余电量", String(format: "%.2f kWh", voltage * ampHours / 1000.0))
            )
        }

        var cells: [Double] = []
        for entity in kind.cellEntities {
            if let v = number(entity).flatMap({ Sanity.check($0, unit: "V") }) { cells.append(v) }
        }

        let note: String?
        switch kind {
        case .battery:
            note = "折算剩余电量 = BMS 实时总压 × BMS 剩余 Ah ÷ 1000，是参考值，不等同实验室可释放电量。"
        case .grid:
            note = "购电与馈网由网关实时功率按正负拆分；正值取电，负值馈电，不用光伏、负载与电池差值猜测。"
        case .inverter:
            note = "码值与说明取自说明书「7.1 报错代码」；本机只接一路码寄存器，因此只显示主告警。"
        default:
            note = nil
        }

        return DeviceDetail(sections: sections, cells: cells, note: note)
    }
}
