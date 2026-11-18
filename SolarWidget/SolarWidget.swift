import WidgetKit
import SwiftUI
import Foundation
import Network

// MARK: - Widget 数据

struct WidgetData {
    var pv: Double?
    var load: Double?
    var soc: Double?
    var daily: Double?
    var charge: Double?
    var discharge: Double?
    var updated: Date = Date()

    static let empty = WidgetData()

    var batteryPower: Double? {
        guard charge != nil || discharge != nil else { return nil }
        return (charge ?? 0) - (discharge ?? 0)
    }
}

// MARK: - 轻量 HTTP（复用 RawHTTP 思路，避免跨 target 依赖）

private enum WidgetHTTP {
    static func get(_ url: URL, token: String, timeout: TimeInterval = 8) async throws -> Data {
        guard let host = url.host else { throw NSError(domain: "widget", code: 1) }
        let port = url.port ?? 80
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw NSError(domain: "widget", code: 2) }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                    var buf = Data()
                    let lock = NSLock()
                    var done = false
                    func finish(_ r: Result<Data, Error>) {
                        lock.lock(); if done { lock.unlock(); return }; done = true; lock.unlock()
                        conn.cancel(); c.resume(with: r)
                    }
                    func receive() {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                            if let d = data { buf.append(d) }
                            if let e = error { finish(.failure(e)); return }
                            if complete {
                                guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else {
                                    finish(.failure(NSError(domain: "widget", code: 3))); return
                                }
                                finish(.success(Data(buf[sep.upperBound...])))
                            } else { receive() }
                        }
                    }
                    conn.stateUpdateHandler = { state in
                        if case .ready = state {
                            let hostHeader = host.contains(":") ? "[\(host)]" : host
                            var head = "GET \(url.path) HTTP/1.1\r\n"
                            head += "Host: \(hostHeader)\(port == 80 ? "" : ":\(port)")\r\n"
                            head += "Authorization: Bearer \(token)\r\n"
                            head += "Accept: application/json\r\n"
                            head += "Connection: close\r\n\r\n"
                            conn.send(content: Data(head.utf8), completion: .contentProcessed { e in
                                if let e { finish(.failure(e)) }
                            })
                            receive()
                        } else if case .failed(let e) = state {
                            finish(.failure(e))
                        }
                    }
                    conn.start(queue: .global(qos: .utility))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                conn.cancel()
                throw NSError(domain: "widget", code: 4)
            }
            guard let d = try await group.next() else { throw NSError(domain: "widget", code: 5) }
            group.cancelAll()
            return d
        }
    }
}

// MARK: - Provider

struct SolarTimeline: TimelineProvider {
    func placeholder(in context: Context) -> SolarEntry {
        SolarEntry(date: Date(), data: .empty, configured: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SolarEntry) -> Void) {
        completion(SolarEntry(date: Date(), data: .empty, configured: SharedConfig.configured))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SolarEntry>) -> Void) {
        Task {
            var data = WidgetData.empty
            if SharedConfig.configured {
                // 走 WidgetHTTP 逐个读 /api/states，绕开 ATS 对 URLSession 明文 HTTP 的拦截
                data = await fetchViaStates()
            }
            let entry = SolarEntry(date: Date(), data: data, configured: SharedConfig.configured)
            // 15 分钟刷新一次，系统会自动决定实际刷新时机
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchViaStates() async -> WidgetData {
        let base = SharedConfig.url
        let ids = [
            "pv": "sensor.guang_fu_ben_di_wang_guan_pv1_power",
            "load": "sensor.guang_fu_ben_di_wang_guan_load_power",
            "soc": "sensor.guang_fu_ben_di_wang_guan_bms_soc",
            "daily": "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy",
            "charge": "sensor.guang_fu_ben_di_wang_guan_battery_charge_power",
            "discharge": "sensor.guang_fu_ben_di_wang_guan_battery_discharge_power",
        ]
        var d = WidgetData.empty
        for (key, id) in ids {
            guard let url = URL(string: "\(base)/api/states/\(id)") else { continue }
            guard let raw = try? await WidgetHTTP.get(url, token: SharedConfig.token) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let state = obj["state"] as? String, let v = Double(state) else { continue }
            switch key {
            case "pv": d.pv = abs(v) <= 30000 ? v : nil
            case "load": d.load = abs(v) <= 30000 ? v : nil
            case "soc": d.soc = (0...100).contains(v) ? v : nil
            case "daily": d.daily = (0...1_000_000).contains(v) ? v : nil
            case "charge": d.charge = abs(v) <= 30000 ? v : nil
            case "discharge": d.discharge = abs(v) <= 30000 ? v : nil
            default: break
            }
        }
        return d
    }
}

struct SolarEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let configured: Bool
}

// MARK: - View

struct SolarWidgetEntryView: View {
    var entry: SolarTimeline.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if !entry.configured {
                needSetup
            } else {
                switch family {
                case .systemSmall: smallView
                case .systemMedium: mediumView
                default: largeView
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(hex: 0x123F5C), Color(hex: 0x061625)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var batteryText: String {
        guard let c = entry.data.charge, let d = entry.data.discharge else { return "--" }
        if c > 0 && d <= 0 { return "充电 \(Fmt.number(c)) W" }
        if d > 0 && c <= 0 { return "放电 \(Fmt.number(d)) W" }
        return "待机"
    }

    private var needSetup: some View {
        VStack(spacing: 5) {
            Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(WColor.text)
            Text("小组件未读到配置").font(.caption.weight(.semibold)).foregroundStyle(WColor.text)
            Text("打开一次 SolarApp，确认地址和令牌已保存后，再回来添加小组件")
                .font(.caption2).foregroundStyle(WColor.label)
                .multilineTextAlignment(.center)
            Text("地址:\(SharedConfig.url.isEmpty ? "无" : "有") 令牌:\(SharedConfig.token.isEmpty ? "无" : "有")")
                .font(.caption2).foregroundStyle(WColor.label.opacity(0.8))
        }
        .padding(10)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(WColor.cyan).frame(width: 6, height: 6)
                Text("实时发电").font(.system(size: 11, weight: .medium)).foregroundStyle(WColor.label)
            }
            Spacer(minLength: 4)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Fmt.number(entry.data.pv)).font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(WColor.text).minimumScaleFactor(0.7)
                Text("W").font(.system(size: 13, weight: .medium)).foregroundStyle(WColor.label)
            }
            Spacer(minLength: 3)
            HStack(spacing: 4) {
                Text("今日").font(.system(size: 11)).foregroundStyle(WColor.label)
                Text(Fmt.kwh(entry.data.daily)).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WColor.value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 0) {
            // 左侧：核心指标聚焦
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(WColor.cyan).frame(width: 6, height: 6)
                    Text("实时发电").font(.system(size: 12, weight: .medium)).foregroundStyle(WColor.label)
                }
                Spacer(minLength: 2)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Fmt.number(entry.data.pv)).font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(WColor.text).minimumScaleFactor(0.65)
                    Text("W").font(.system(size: 14, weight: .medium)).foregroundStyle(WColor.label)
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WColor.divider).frame(width: 1)
                .padding(.vertical, 10)

            // 右侧：次要信息竖排
            VStack(alignment: .leading, spacing: 0) {
                sideLine("今日发电", Fmt.kwh(entry.data.daily))
                sideLine("电池 SOC", Fmt.percent(entry.data.soc))
                sideLine("当前负载", Fmt.watt(entry.data.load))
            }
            .frame(width: 128, alignment: .leading)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(WColor.cyan).frame(width: 7, height: 7)
                Text("光伏监控").font(.system(size: 14, weight: .semibold)).foregroundStyle(WColor.text)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(Fmt.number(entry.data.pv)).font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(WColor.text).minimumScaleFactor(0.6)
                Text("W").font(.system(size: 15, weight: .medium)).foregroundStyle(WColor.label)
            }
            VStack(spacing: 8) {
                HStack(spacing: 10) { metric("今日发电", Fmt.kwh(entry.data.daily)); metric("电池 SOC", Fmt.percent(entry.data.soc)) }
                HStack(spacing: 10) { metric("当前负载", Fmt.watt(entry.data.load)); metric("电池状态", batteryText) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sideLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(WColor.label)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(WColor.value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(WColor.label)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(WColor.value)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(WColor.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Widget 配色（与主 App 同为 94/81% 柔和色阶）

private enum WColor {
    static let text = Color(hex: 0xF2F7FC)
    static let value = Color(hex: 0xE4EFF8)
    static let label = Color(hex: 0xCFDEEB)
    static let cyan = Color(hex: 0x41F4FF)
    static let divider = Color.white.opacity(0.16)
    static let tile = Color.white.opacity(0.07)
}

// MARK: - Format (与 App 内一致，避免跨 target 耦合)

private enum Fmt {
    static func number(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.0f", v)
    }
    static func watt(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.0f W", v)
    }
    static func kwh(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.2f kWh", v)
    }
    static func percent(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.0f%%", v)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

@main
struct SolarWidgetBundle: WidgetBundle {
    var body: some Widget {
        SolarWidget()
    }
}

struct SolarWidget: Widget {
    let kind = "SolarWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SolarTimeline()) { entry in
            SolarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("光伏监控")
        .description("实时功率、今日发电与电池状态")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
