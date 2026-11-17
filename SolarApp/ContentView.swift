import SwiftUI
import UIKit

// MARK: - 设计系统
//
// 圆角是同心层级，不是所有卡片都用屏幕半径。
// iPhone 17 Pro 屏幕圆角 62pt（ScreenCorners 实测），卡片距边 14pt，
// 外层容器 = 62 − 14 = 48pt，弧线与屏幕平行同心；内层按体量递减。

enum Design {
    static var screenRadius: CGFloat {
        if let r = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat, r > 0 {
            return r
        }
        return 62
    }
    static let screenPadding: CGFloat = 14
    static var containerRadius: CGFloat { max(20, screenRadius - screenPadding) }
    static let cardRadius: CGFloat = 28
    static let chipRadius: CGFloat = 16

    static let gap: CGFloat = 12
    static let padH: CGFloat = 14

    static let titleFont = Font.system(size: 17, weight: .semibold)
    static let cardValue = Font.system(size: 23, weight: .bold, design: .rounded)
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 10.5, weight: .medium)

    static let springy = Animation.spring(response: 0.45, dampingFraction: 0.84)
    static let snappy = Animation.snappy(duration: 0.34)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
}

enum Palette {
    static let bg = Color(hex: 0x0B1118)
    static let card = Color(hex: 0x1A2430)
    static let accent = Color(hex: 0xF5A623)
    static let cyan = Color(hex: 0x41F4FF)
    static let text = Color(hex: 0xF6FBFF)
    static let dim = Color(hex: 0x9FB6C9)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 格式化

enum Fmt {
    private static let intFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func watt(_ v: Double?) -> String {
        guard let v else { return "--" }
        let n = Int(v.rounded())
        return (intFmt.string(from: NSNumber(value: n)) ?? "\(n)") + " W"
    }

    static func kwh(_ v: Double?, digits: Int = 1) -> String {
        guard let v else { return "--" }
        return String(format: "%.\(digits)f kWh", v)
    }

    static func percent(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.0f%%", v)
    }

    static func clock(_ d: Date) -> String { clockFmt.string(from: d) }
}

// MARK: - 主视图

struct ContentView: View {
    @AppStorage("haURL") private var haURL: String = ""
    @AppStorage("haToken") private var haToken: String = ""

    @State private var data: SolarData = .empty
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var appeared = false

    private var configured: Bool {
        !haURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !haToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(kind: data.weather)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Design.gap) {
                    header
                        .padding(.top, 6)

                    LuminaHero(data: data)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)

                    ForecastBar(data: data)

                    metricsGrid

                    energyRow

                    panelButton
                }
                .padding(.horizontal, Design.padH)
                .padding(.bottom, 34)
            }
            .refreshable { await refresh() }

            if !configured {
                configHint
            }
        }
        .preferredColorScheme(.dark)
        .animation(Design.snappy, value: data)
        .task {
            withAnimation(Design.springy) { appeared = true }
            await refresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(haURL: $haURL, haToken: $haToken)
                .presentationCornerRadius(Design.containerRadius)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("光伏监控")
                    .font(Design.titleFont)
                    .foregroundStyle(Palette.text)
                Text(statusLine)
                    .font(Design.caption)
                    .foregroundStyle(errorText == nil ? Palette.dim : Color(hex: 0xFF9B9B))
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var statusLine: String {
        if let e = errorText { return e }
        if isLoading && data.updatedAt.timeIntervalSince1970 < 100 { return "正在读取…" }
        return "更新于 \(Fmt.clock(data.updatedAt))"
    }

    // MARK: 四个指标

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Design.gap),
                      GridItem(.flexible(), spacing: Design.gap)],
            spacing: Design.gap
        ) {
            MetricCard(
                icon: "sun.max.fill",
                tint: Color(hex: 0xFFD166),
                title: "今日发电",
                value: Fmt.kwh(data.daily),
                progress: data.forecastProgress,
                footnote: forecastFootnote
            )
            MetricCard(
                icon: "chart.line.uptrend.xyaxis",
                tint: Color(hex: 0x7FD8FF),
                title: "今日预测",
                value: Fmt.kwh(data.forecastToday),
                progress: nil,
                footnote: data.forecastRemaining.map { "剩余 \(Fmt.kwh($0))" }
            )
            MetricCard(
                icon: "battery.75percent",
                tint: Color(hex: 0x6FE7C7),
                title: "电池 SOC",
                value: Fmt.percent(data.soc),
                progress: data.soc.map { min(max($0 / 100, 0), 1) },
                footnote: batteryFootnote
            )
            MetricCard(
                icon: "house.fill",
                tint: Color(hex: 0xFFB86B),
                title: "当前负载",
                value: Fmt.watt(data.load),
                progress: nil,
                footnote: data.grid.map { "市电 \(Fmt.watt($0))" }
            )
        }
    }

    private var forecastFootnote: String? {
        guard let p = data.forecastProgress else { return nil }
        return "预测完成 \(Int((p * 100).rounded()))%"
    }

    private var batteryFootnote: String? {
        guard let p = data.batteryPower else { return nil }
        if p > 20 { return "充电 \(Fmt.watt(p))" }
        if p < -20 { return "放电 \(Fmt.watt(-p))" }
        return "待机"
    }

    // MARK: 累计发电

    private var energyRow: some View {
        HStack {
            Label("累计发电", systemImage: "bolt.fill")
                .font(Design.label)
                .foregroundStyle(Palette.dim)
            Spacer()
            Text(Fmt.kwh(data.total, digits: 0))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.card.opacity(0.62), in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }

    // MARK: 打开完整面板

    private var panelButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if let url = panelURL { UIApplication.shared.open(url) }
        } label: {
            HStack {
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("打开完整面板")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .stroke(Palette.accent.opacity(0.38), lineWidth: 0.8)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var panelURL: URL? {
        let base = haURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/solar-board/solar")
    }

    // MARK: 未配置提示

    private var configHint: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.accent)
            Text("还没有配置 HA 地址和令牌")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text("点右上角齿轮填入地址与长期访问令牌")
                .font(Design.caption)
                .foregroundStyle(Palette.dim)
            Button("去配置") { showSettings = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Palette.accent, in: Capsule())
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
        )
        .padding(.horizontal, 34)
    }

    // MARK: 取数

    @MainActor
    private func refresh() async {
        guard configured else {
            errorText = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = HAClient(baseURL: haURL, token: haToken)
            let fresh = try await client.fetchSolar()
            withAnimation(Design.snappy) {
                data = fresh
                errorText = nil
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 天气背景

struct WeatherBackdrop: View {
    let kind: WeatherKind

    var body: some View {
        ZStack {
            Palette.bg
            Image(kind.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x03182D).opacity(0.10),
                            Color(hex: 0x03182D).opacity(0.34),
                            Color(hex: 0x02101F).opacity(0.80),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [Color(hex: 0xF5A623).opacity(0.10), .clear],
                        startPoint: .topTrailing,
                        endPoint: .center
                    )
                )
                .animation(.easeInOut(duration: 0.7), value: kind)
        }
    }
}

// MARK: - 全景卡（能流 + 浮标）

struct LuminaHero: View {
    let data: SolarData
    @State private var dashPhase: CGFloat = 0

    private let boxW: CGFloat = 1617
    private let boxH: CGFloat = 971

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Image("LuminaEntities")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                flows(w: w, h: h)

                // 光伏 (left 7.4%, top 28.7%)
                buoyPV
                    .position(x: w * 0.074 + 44, y: h * 0.287 + 15)

                // 住宅负载 (left 51.8%, top 19%)
                buoyLoad
                    .position(x: w * 0.518, y: h * 0.19 + 15)

                // 电池 (left 24.2%, bottom 17.6%)
                buoyBattery
                    .position(x: w * 0.242 + 28, y: h * 0.824 - 15)

                // 市电 (right 5.5%, top 30%)
                buoyGrid
                    .position(x: w * 0.945 - 22, y: h * 0.30 + 18)
            }
        }
        .aspectRatio(boxW / boxH, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        )
        .shadow(color: Color(hex: 0x000F24).opacity(0.30), radius: 18, y: 10)
        .onAppear {
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                dashPhase = 220
            }
        }
    }

    // MARK: 能流线

    private func flows(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            glow(.pv, active: activePV, w: w, h: h)
            glow(.load, active: activeLoad, w: w, h: h)
            glow(.battery, active: activeBattery, w: w, h: h)
            glow(.grid, active: activeGrid, w: w, h: h)

            pulse(.pv, active: activePV, w: w, h: h)
            pulse(.load, active: activeLoad, w: w, h: h)
            pulse(.battery, active: activeBattery, w: w, h: h)
            pulse(.grid, active: activeGrid, w: w, h: h)

            Circle()
                .fill(Palette.cyan.opacity(0.85))
                .frame(width: max(4, w * 0.011), height: max(4, w * 0.011))
                .blur(radius: 2)
                .position(x: w * (1010 / boxW), y: h * (640 / boxH))
        }
        .allowsHitTesting(false)
    }

    private func glow(_ route: FlowShape, active: Bool, w: CGFloat, h: CGFloat) -> some View {
        route.path(in: CGSize(width: w, height: h))
            .stroke(Palette.cyan.opacity(active ? 0.30 : 0.05), lineWidth: 7)
            .blur(radius: 5)
    }

    private func pulse(_ route: FlowShape, active: Bool, w: CGFloat, h: CGFloat) -> some View {
        route.path(in: CGSize(width: w, height: h))
            .stroke(
                LinearGradient(
                    colors: [Color(hex: 0x78F8FF), Color(hex: 0xD9FFFF), Color(hex: 0x44E5FF)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: max(1.4, w * 0.006),
                    lineCap: .round,
                    dash: [max(18, w * 0.16), max(26, w * 0.20)],
                    dashPhase: dashPhase
                )
            )
            .opacity(active ? 0.95 : 0)
            .animation(.easeInOut(duration: 0.4), value: active)
    }

    private var activePV: Bool { (data.pv1 ?? 0) > 20 }
    private var activeLoad: Bool { (data.load ?? 0) > 20 }
    private var activeBattery: Bool { abs(data.batteryPower ?? 0) > 20 }
    private var activeGrid: Bool { abs(data.grid ?? 0) > 20 }

    // MARK: 浮标

    private var buoyText: CGFloat { 10 }

    private func buoy<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x021424).opacity(0.86), Color(hex: 0x083448).opacity(0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: 0xE0FCFF).opacity(0.45), lineWidth: 0.6)
            )
            .shadow(color: Color(hex: 0x19EEFF).opacity(0.45), radius: 5)
            .foregroundStyle(Palette.cyan)
            .fixedSize()
    }

    private var buoyPV: some View {
        buoy {
            VStack(alignment: .leading, spacing: 1) {
                Text("S1: \(Fmt.watt(data.pv1))")
                    .font(.system(size: buoyText, weight: .heavy))
                Text("S2: \(data.pv2 == nil ? "未接入" : Fmt.watt(data.pv2))")
                    .font(.system(size: buoyText - 1, weight: .semibold))
            }
            .italic()
        }
    }

    private var buoyLoad: some View {
        buoy {
            VStack(spacing: 0) {
                Text(Fmt.watt(data.load))
                    .font(.system(size: buoyText + 1, weight: .heavy))
                Text("住宅负载")
                    .font(.system(size: buoyText - 1.5, weight: .semibold))
                    .opacity(0.85)
            }
        }
    }

    private var buoyBattery: some View {
        buoy {
            VStack(spacing: 0) {
                Text(Fmt.percent(data.soc))
                    .font(.system(size: buoyText + 1, weight: .heavy))
                Text(Fmt.watt(abs(data.batteryPower ?? 0)))
                    .font(.system(size: buoyText - 1, weight: .semibold))
            }
        }
    }

    private var buoyGrid: some View {
        buoy {
            VStack(alignment: .trailing, spacing: 0) {
                Text("市电")
                    .font(.system(size: buoyText - 2, weight: .semibold))
                    .opacity(0.85)
                Text(Fmt.watt(data.grid))
                    .font(.system(size: buoyText, weight: .heavy))
                Text(gridStateText)
                    .font(.system(size: buoyText - 2, weight: .semibold))
                    .opacity(0.85)
            }
        }
    }

    private var gridStateText: String {
        guard let g = data.grid else { return "--" }
        if abs(g) < 50 { return "正常" }
        return g > 0 ? "取电" : "馈电"
    }
}

// MARK: - 能流路径（与 HA 面板 SVG 同源，viewBox 1617×971）

enum FlowShape {
    case pv, load, battery, grid

    func path(in size: CGSize) -> Path {
        let sx = size.width / 1617
        let sy = size.height / 971
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }

        var path = Path()
        switch self {
        case .pv:
            path.move(to: p(470, 580))
            path.addCurve(to: p(995, 640), control1: p(625, 575), control2: p(770, 645))
        case .load:
            path.move(to: p(1010, 627))
            path.addCurve(to: p(910, 365), control1: p(978, 548), control2: p(935, 455))
        case .battery:
            path.move(to: p(995, 655))
            path.addCurve(to: p(735, 765), control1: p(905, 690), control2: p(820, 730))
        case .grid:
            path.move(to: p(1390, 510))
            path.addCurve(to: p(1025, 640), control1: p(1280, 540), control2: p(1160, 610))
        }
        return path
    }
}

// MARK: - 预测条

struct ForecastBar: View {
    let data: SolarData

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: data.weather.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Palette.text.opacity(0.92))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("今日预计")
                        .foregroundStyle(Palette.dim)
                    Text(Fmt.kwh(data.forecastToday))
                        .foregroundStyle(Palette.text)
                        .fontWeight(.semibold)
                    Text("，剩余")
                        .foregroundStyle(Palette.dim)
                    Text(Fmt.kwh(data.forecastRemaining))
                        .foregroundStyle(Palette.text)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12.5))

                Text(secondLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var secondLine: String {
        var parts: [String] = [data.weather.label]
        if let t = data.forecastTomorrow {
            parts.append("明日预计 \(Fmt.kwh(t))")
        }
        if let d = data.daily, let f = data.forecastToday, f > 1 {
            let pct = Int((min(d / f, 1) * 100).rounded())
            parts.append("已完成 \(pct)%")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 指标卡

struct MetricCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let progress: Double?
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Design.label)
                    .foregroundStyle(Palette.dim)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(Design.cardValue)
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.55), tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
                .animation(Design.snappy, value: progress)
            }

            if let footnote {
                Text(footnote)
                    .font(Design.caption)
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card.opacity(0.62), in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }
}

// MARK: - 按压反馈

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Design.press, value: configuration.isPressed)
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @Binding var haURL: String
    @Binding var haToken: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant 地址") {
                    TextField("http://192.168.31.88:8123", text: $haURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("外网用 IPv6 时必须写成 http://[地址]:8123，方括号不能省")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("长期访问令牌") {
                    SecureField("eyJ0eXAiOiJKV1Qi...", text: $haToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("HA → 左下角个人资料 → 安全 → 长期访问令牌 → 创建")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("完成") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
