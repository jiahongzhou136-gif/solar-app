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

    private var needSetup: some View {
        VStack(spacing: 6) {
            Image(systemName: "sun.max.fill").font(.title).foregroundStyle(.white)
            Text("请先在 App 内配置 HA 地址和令牌").font(.caption).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("光伏").font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(Fmt.watt(entry.data.pv)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 4) {
                Text("今日").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(Fmt.kwh(entry.data.daily)).font(.caption.weight(.semibold)).foregroundStyle(.white)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("实时功率").font(.caption2).foregroundStyle(.white.opacity(0.7))
                Text(Fmt.watt(entry.data.pv)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            Divider().background(Color.white.opacity(0.2))
            metric("今日发电", Fmt.kwh(entry.data.daily))
            Divider().background(Color.white.opacity(0.2))
            metric("电池 SOC", Fmt.percent(entry.data.soc))
            Divider().background(Color.white.opacity(0.2))
            metric("负载", Fmt.watt(entry.data.load))
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("光伏监控").font(.headline).foregroundStyle(.white); Spacer() }
            HStack(spacing: 16) {
                metric("实时功率", Fmt.watt(entry.data.pv))
                metric("今日发电", Fmt.kwh(entry.data.daily))
            }
            HStack(spacing: 16) {
                metric("电池 SOC", Fmt.percent(entry.data.soc))
                metric("当前负载", Fmt.watt(entry.data.load))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Format (与 App 内一致，避免跨 target 耦合)

private enum Fmt {
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
