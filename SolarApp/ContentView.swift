import SwiftUI
import UIKit

// MARK: - 设计系统
//
// iPhone 17 Pro 同心圆角：屏幕 62pt − 边距 14pt = 48pt 容器；
// 整行卡片 28pt、半宽卡片 22pt、图标 10pt，全部 .continuous（超椭圆）。

enum Design {
    static var screenRadius: CGFloat {
        if let r = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat, r > 0 {
            return r
        }
        return 62
    }
    static let screenPadding: CGFloat = 14
    static var containerRadius: CGFloat { max(20, screenRadius - screenPadding) }

    static let rowRadius: CGFloat = 28
    static let cardRadius: CGFloat = 22
    static let iconRadius: CGFloat = 10
    static let chipRadius: CGFloat = 12
    static let buoyRadius: CGFloat = 7
    static let controlRadius: CGFloat = 15

    static let gap: CGFloat = 9
    static let padH: CGFloat = 14

    static let titleFont = Font.system(size: 17, weight: .semibold)
    static let cardValue = Font.system(size: 23, weight: .bold, design: .rounded)
    static let label = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 10, weight: .regular)

    static let springy = Animation.spring(response: 0.45, dampingFraction: 0.84)
    static let snappy = Animation.snappy(duration: 0.34)
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.7)
}

enum Palette {
    // 与 HA 面板 CSS 变量 1:1：--text #f7fbff / --muted #b7cfdf
    static let bg = Color(hex: 0x0B1118)
    static let accent = Color(hex: 0xF5A623)
    static let cyan = Color(hex: 0x41F4FF)
    /// HA --text：主文字与数值
    static let text = Color(hex: 0xF7FBFF)
    /// HA 卡片标题：比主文字略柔
    static let title = Color(hex: 0xEAF3FA)
    /// HA --muted：副行、脚注
    static let dim = Color(hex: 0xB7CFDF)
    /// 三级提示：沿用 HA detail-board small #a9c2d6
    static let sub = Color(hex: 0xA9C2D6)
    static let danger = Color(hex: 0xFFB4B4)
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

    private static let twoFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
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

    static func temp(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.1f °C", v)
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
    @State private var selected: DeviceKind?
    @State private var consecutiveFailures = 0
    @Namespace private var zoomNS

    private var configured: Bool {
        !haURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !haToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var client: HAClient { HAClient(baseURL: haURL, token: haToken) }

    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackdrop(kind: data.weather, isNight: data.isNight)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Design.gap) {
                        header
                            .padding(.top, 2)

                        LuminaHero(data: data)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        ForecastBar(data: data)

                        HStack(spacing: Design.gap) {
                            deviceCard(.pv1)
                            deviceCard(.inverter)
                        }

                        batteryCard

                        HStack(spacing: Design.gap) {
                            deviceCard(.grid)
                            deviceCard(.load)
                        }

                        energyCard
                    }
                    .padding(.horizontal, Design.padH)
                    .padding(.bottom, 20)
                }
                .refreshable { await refresh(haptic: true) }

                if !configured {
                    configHint
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selected) { kind in
                DeviceDetailView(kind: kind, client: client)
                    .navigationTransition(.zoom(sourceID: kind.id, in: zoomNS))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(haURL: $haURL, haToken: $haToken) {
                    Task { await refresh() }
                }
                .presentationCornerRadius(Design.containerRadius)
                .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            withAnimation(Design.springy) { appeared = true }
            SharedConfig.save(url: haURL, token: haToken)
            await refreshLoop()
        }
        .onChange(of: haURL) { SharedConfig.save(url: haURL, token: haToken) }
        .onChange(of: haToken) { SharedConfig.save(url: haURL, token: haToken) }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("光伏监控")
                    .font(Design.titleFont)
                    .foregroundStyle(Palette.text)
                Text(statusLine)
                    .font(Design.caption)
                    .foregroundStyle(errorText == nil ? Palette.dim : Palette.danger)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .modifier(GlassCircle())
        }
    }

    private var statusLine: String {
        if let e = errorText { return e }
        if data.isEmptyReading {
            return isLoading ? "正在读取…" : "暂无数据，下拉刷新"
        }
        return "更新于 \(Fmt.clock(data.updatedAt))"
    }

    // MARK: 半宽卡

    private func deviceCard(_ kind: DeviceKind) -> some View {
        let (value, footnote) = summary(for: kind)
        return VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    iconBadge(kind.icon)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 12)

                Text(kind.title)
                    .font(Design.label)
                    .foregroundStyle(Palette.title)
                Text(value)
                    .font(Design.cardValue)
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                Text(footnote)
                    .font(Design.caption)
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
            // 通透玻璃下靠文字投影保证浅色天气背景上的可读性
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
            .modifier(GlassCard(radius: Design.cardRadius))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selected = kind
            }
            .matchedTransitionSource(id: kind.id, in: zoomNS)
    }

    private func iconBadge(_ icon: HAIcon) -> some View {
        icon.body
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
    }

    private func summary(for kind: DeviceKind) -> (String, String) {
        switch kind {
        case .pv1:
            return (Fmt.watt(data.pv1), "PV2 未接入")
        case .inverter:
            let temp = data.inverterTemp.map { String(format: "实时 · %.1f °C", $0) } ?? "实时"
            // 与面板 _inverterPowerKey() 一致：现场无 inverter_output_power 时退回 load_power
            return (Fmt.watt(data.load ?? data.pvTotal ?? data.pv1), temp)
        case .battery:
            // 与 HA _derivedState 同口径：只看互斥的正值通道
            let charging = (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0
            let discharging = (data.discharge ?? 0) > 0 && (data.charge ?? 0) <= 0
            if charging { return ("充电 \(Fmt.watt(data.charge))", "能量流入") }
            if discharging { return ("放电 \(Fmt.watt(data.discharge))", "能量流出") }
            return ("待机 0 W", "待机")
        case .grid:
            let g = data.grid ?? 0
            let direction = abs(g) < 50 ? "正常" : (g > 0 ? "取电" : "馈电")
            return (Fmt.watt(data.grid), "\(direction) · 市电\(g > 0 ? "流入" : (g < 0 ? "流出" : "待机"))")
        case .load:
            return (Fmt.watt(data.load), "当前用电")
        }
    }

    // MARK: 电池整行卡

    private var batteryCard: some View {
        HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        iconBadge(DeviceKind.battery.icon)
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 12)

                    Text("储能电池")
                        .font(Design.label)
                        .foregroundStyle(Palette.title)
                    Text(batteryHeadline)
                        .font(Design.cardValue)
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                    Text(batterySubline)
                        .font(Design.caption)
                        .foregroundStyle(Palette.dim)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)

                BatteryGlyph(soc: data.soc, charging: (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0)
                    .frame(width: 66, height: 100)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
        .modifier(GlassCard(radius: Design.rowRadius))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selected = .battery
        }
        .matchedTransitionSource(id: DeviceKind.battery.id, in: zoomNS)
    }

    private var batteryHeadline: String {
        let charging = (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0
        let discharging = (data.discharge ?? 0) > 0 && (data.charge ?? 0) <= 0
        if charging { return "充电 \(Fmt.watt(data.charge))" }
        if discharging { return "放电 \(Fmt.watt(data.discharge))" }
        return "待机 0 W"
    }

    private var batterySubline: String {
        let charging = (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0
        let discharging = (data.discharge ?? 0) > 0 && (data.charge ?? 0) <= 0
        if charging { return "能量流入" }
        if discharging { return "能量流出" }
        return "待机"
    }

    // MARK: 今日能量

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日能量")
                .font(Design.label)
                .foregroundStyle(Palette.title)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                energyItem("日充电", Fmt.kwh(data.dailyCharge, digits: 2))
                energyItem("日放电", Fmt.kwh(data.dailyDischarge, digits: 2))
                energyItem("日发电", Fmt.kwh(data.dailyPv, digits: 2))
                energyItem("累计发电", Fmt.kwh(data.totalPv, digits: 1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    private func energyItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Design.caption)
                .foregroundStyle(Palette.dim)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 未配置

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
        .modifier(GlassCard(radius: Design.rowRadius))
        .padding(.horizontal, 34)
    }

    // MARK: 取数

    /// Modbus 6 段 × 1.2s throttle ≈ 7.2s 一轮，2 秒轮询足以跟上变化
    @MainActor
    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            if Task.isCancelled { break }
            // 详情页打开时主界面被覆盖，暂停轮询避免两路请求叠加
            if selected == nil {
                await refresh()
            }
        }
    }

    @MainActor
    private func refresh(haptic: Bool = false) async {
        guard configured else {
            errorText = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await client.fetchSolar()
            // 不再用 withAnimation 包住整棵树：数值自身已有 .contentTransition(.numericText())，
            // 整树动画会在每 2 秒刷新时重算所有玻璃图层，是滑屏掉帧的主因。
            data = fresh
            errorText = nil
            consecutiveFailures = 0
            if haptic {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        } catch {
            consecutiveFailures += 1
            errorText = HAError.describe(error)
            // 连续失败后清空旧读数，避免长期停在固定数字误导
            if consecutiveFailures >= 3, !data.isEmptyReading {
                data = .empty
            }
        }
    }
}

// MARK: - 玻璃修饰器

struct GlassCard: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 与 HA .card 同源：蓝灰渐变底 + 玻璃折射。
            // 底色够浓度，文字才能用 HA 的 --text/--muted 而不刺眼。
            content
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x477594).opacity(0.46), Color(hex: 0x0A3150).opacity(0.34)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .glassEffect(
                    .clear.tint(Color(hex: 0x1A3A55).opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.10), Color.white.opacity(0.30)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        } else {
            content
                .background(
                    Color(hex: 0x081725).opacity(0.55),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                )
        }
    }
}

struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear, in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
        }
    }
}

// MARK: - 卡片按压

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Design.press, value: configuration.isPressed)
    }
}

// MARK: - 电池图形

struct BatteryGlyph: View {
    let soc: Double?
    let charging: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let level = min(max((soc ?? 0) / 100, 0), 1)

            ZStack {
                RoundedRectangle(cornerRadius: w * 0.32, style: .continuous)
                    .fill(Color(hex: 0x041E30).opacity(0.86))

                RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x5DF2DC), Color(hex: 0x29C9DF), Color(hex: 0x168FD6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(6, (h - 10) * level))
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                Text(Fmt.percent(soc))
                    .font(.system(size: w * 0.27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x00192F).opacity(0.55), radius: 3, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(
                RoundedRectangle(cornerRadius: w * 0.32, style: .continuous)
                    .stroke(charging ? Color(hex: 0x7DEFEF) : Color(hex: 0x5FD6E6), lineWidth: 2)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x7DEFEF))
                    .frame(width: w * 0.38, height: 6)
                    .offset(y: -6)
            }
        }
    }
}

// MARK: - 动态天气背景

struct WeatherBackdrop: View {
    let kind: WeatherKind
    var isNight: Bool = false

    @State private var drift: CGFloat = -1
    @State private var zoom: CGFloat = 1.04
    @State private var sunPulse: CGFloat = 0.9
    @State private var moonPulse: CGFloat = 0.86

    private var imageName: String {
        isNight ? "WeatherNight" : kind.imageName
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.bg

                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoom)
                    .offset(x: drift * 10, y: drift * 5)
                    .clipped()

                if !isNight && kind == .sunny { sunOrb(in: geo.size) }
                if isNight {
                    starField(in: geo.size)
                    moonOrb(in: geo.size)
                }
                if kind == .rain { RainLayer().allowsHitTesting(false) }

                Clouds(size: geo.size, kind: kind, isNight: isNight)

                LinearGradient(
                    colors: isNight
                        ? [Color(hex: 0x01060E).opacity(0.34),
                           Color(hex: 0x020A16).opacity(0.52),
                           Color(hex: 0x01060E).opacity(0.88)]
                        : [Color(hex: 0x03182D).opacity(0.10),
                           Color(hex: 0x03182D).opacity(0.32),
                           Color(hex: 0x02101F).opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.7), value: isNight)
        .onAppear {
            // 不用 drawingGroup：它会把动态图层烘焙成静态位图导致背景不动。
            // 用 linear 慢速循环，兼顾动感与滚动性能。
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: true)) {
                drift = 1
                zoom = 1.09
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: true)) {
                sunPulse = 1.06
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
                moonPulse = 0.95
            }
        }
    }

    private func sunOrb(in size: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: 0xFFF8CE).opacity(0.95),
                        Color(hex: 0xFFE47B).opacity(0.55),
                        Color(hex: 0xFFD248).opacity(0.18),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 90
                )
            )
            .frame(width: 180, height: 180)
            .scaleEffect(sunPulse)
            .position(x: size.width * 0.83, y: size.height * 0.10)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    private func moonOrb(in size: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, Color(hex: 0xE6F2FF), Color(hex: 0x9AC4EA).opacity(0.5), .clear],
                    center: UnitPoint(x: 0.38, y: 0.34),
                    startRadius: 2,
                    endRadius: 60
                )
            )
            .frame(width: 110, height: 110)
            .scaleEffect(moonPulse)
            .position(x: size.width * 0.80, y: size.height * 0.09)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    private func starField(in size: CGSize) -> some View {
        Canvas { ctx, canvas in
            for i in 0..<44 {
                let seedX = Double((i * 37) % 100) / 100
                let seedY = Double((i * 61) % 58) / 100
                let r = 0.7 + Double(i % 3) * 0.5
                let rect = CGRect(x: seedX * canvas.width, y: seedY * canvas.height, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Clouds: View {
    let size: CGSize
    let kind: WeatherKind
    var isNight: Bool = false

    private var baseOpacity: Double {
        if isNight { return 0.40 }
        switch kind {
        case .sunny:  return 0.30
        case .cloudy: return 0.82
        case .rain:   return 0.52
        }
    }

    private var dark: Bool { isNight || kind == .rain }

    var body: some View {
        // 三层云合并到一个 Canvas、12fps，避免 3 个 withAnimation 在滚动时持续合成
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            Canvas { ctx, s in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let layers: [(CGFloat, CGFloat, Double, Double, CGFloat)] = [
                    (0.04, 0.92, 18, 0, 0.55),
                    (0.28, 0.82, 24, -8, -0.52),
                    (0.58, 1.02, 29, -15, 0.60),
                ]
                for (idx, layer) in layers.enumerated() {
                    let (yP, wR, dur, delay, shift) = layer
                    let period = dur * 2
                    let raw = (t / period + Double(delay) / period).truncatingRemainder(dividingBy: 1)
                    let tri = 1 - abs(raw * 2 - 1)          // 0→1→0 往复
                    let x = (tri - 0.5) * shift * s.width
                    let cw = s.width * wR
                    let ch = s.height * 0.22
                    let rect = CGRect(x: x + (s.width - cw) / 2, y: s.height * yP - ch / 2,
                                      width: cw, height: ch)
                    let colors = dark
                        ? [Color(hex: 0x738A9B).opacity(0.72), Color(hex: 0x274057).opacity(0.35), Color.clear]
                        : [Color(hex: 0xFAFDFF).opacity(0.82), Color(hex: 0xCAE1EB).opacity(0.34), Color.clear]
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: colors),
                            center: CGPoint(x: rect.midX, y: rect.midY),
                            startRadius: 8,
                            endRadius: cw * 0.5
                        )
                    )
                    _ = idx
                }
            }
        }
        .opacity(baseOpacity)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private struct RainLayer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<64 {
                    let seed = Double((i * 29) % 100) / 100.0
                    let speed = 0.75 + Double(i % 5) * 0.16
                    let phase = (t * speed + seed * 3.7).truncatingRemainder(dividingBy: 1.0)
                    let x = seed * (size.width + 60) - 30
                    let y = phase * (size.height + 120) - 60
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - 5, y: y + 20))
                    ctx.stroke(p, with: .color(Color(hex: 0xE3F4FF).opacity(0.42)), lineWidth: 0.9)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 全景卡

struct LuminaHero: View {
    let data: SolarData
    @State private var glowIn: CGFloat = 0

    private let boxW: CGFloat = 1617
    private let boxH: CGFloat = 971

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 图片、能流线、浮标共用同一变换（放大 8% + 上移 3%），保持坐标对齐
                ZStack {
                    Image("LuminaEntities")
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)

                    flows(w: w, h: h)

                    buoyPV.position(x: w * 0.115, y: h * 0.315)
                    buoyLoad.position(x: w * 0.518, y: h * 0.215)
                    buoyBattery.position(x: w * 0.268, y: h * 0.790)
                    buoyGrid.position(x: w * 0.900, y: h * 0.330)
                }
                .frame(width: w, height: h)
                .scaleEffect(1.08)
                .offset(y: -h * 0.03)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        // HA 手机端权威比例 5/3 = 1.667，建筑图保持此比例，靠 108% 放大让主体饱满
        .aspectRatio(boxW / boxH, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { glowIn = 1 }
        }
    }

    /// 能流完全由 TimelineView 驱动：只有有功率的线路才推进相位。
    /// 相比 4 个 repeatForever + withAnimation，滚动时不会反复触发隐式动画。
    private func flows(w: CGFloat, h: CGFloat) -> some View {
        // 30fps：每帧移动约 3pt，肉眼平滑。速度 90pt/s 约 0.8 秒走完一个 dash 周期。
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            FlowCanvas(
                w: w, h: h,
                phase: timeline.date.timeIntervalSinceReferenceDate * 90,
                pv: activePV, load: activeLoad,
                battery: activeBattery, batteryReverse: batteryDischarging,
                grid: activeGrid, gridReverse: gridExporting
            )
        }
        .allowsHitTesting(false)
        .opacity(glowIn)
    }


    private var activePV: Bool { (data.pv1 ?? 0) > 20 }
    private var activeLoad: Bool { (data.load ?? 0) > 20 }
    private var activeBattery: Bool {
        // 与 HA _derivedState 一致：只看两个互斥正值，不看带符号原始功率
        (data.charge ?? 0) > 0 || (data.discharge ?? 0) > 0
    }
    private var activeGrid: Bool {
        // 面板从 grid_power_raw 拆分：正=取电，负=馈电，零=正常
        abs(data.grid ?? 0) > 20
    }
    /// 电池：只有 discharge 单独为正才是放电；两者同正按 HA 判为 unknown（静止）
    private var batteryDischarging: Bool {
        (data.discharge ?? 0) > 0 && !((data.charge ?? 0) > 0)
    }
    /// 市电：原始值为负才是馈电（面板 fallback 用 grid_power_raw 拆分）
    private var gridExporting: Bool { (data.grid ?? 0) < 0 }
    /// 电池方向：充电/放电/待机，供浮标与图例同步
    private var batteryDirection: String {
        if (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0 { return "充电" }
        if (data.discharge ?? 0) > 0 && (data.charge ?? 0) <= 0 { return "放电" }
        return "待机"
    }

    private var buoyText: CGFloat { 10 }

    private func buoy<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                Color(hex: 0x021424).opacity(0.82),
                in: RoundedRectangle(cornerRadius: Design.buoyRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.buoyRadius, style: .continuous)
                    .stroke(Color(hex: 0xE0FCFF).opacity(0.45), lineWidth: 0.6)
            )
            .shadow(color: Color(hex: 0x19EEFF).opacity(0.42), radius: 4)
            .foregroundStyle(Palette.cyan)
            .fixedSize()
    }

    private var buoyPV: some View {
        buoy {
            VStack(alignment: .leading, spacing: 1) {
                Text("S1: \(Fmt.watt(data.pv1))").font(.system(size: buoyText, weight: .heavy))
                Text("S2: 未接入").font(.system(size: buoyText - 1, weight: .semibold))
            }
            .italic()
        }
    }

    private var buoyLoad: some View {
        buoy {
            VStack(spacing: 0) {
                Text(Fmt.watt(data.load)).font(.system(size: buoyText + 1, weight: .heavy))
                Text("住宅负载").font(.system(size: buoyText - 1.5, weight: .semibold)).opacity(0.85)
            }
        }
    }

    private var buoyBattery: some View {
        buoy {
            VStack(spacing: 0) {
                Text(Fmt.percent(data.soc)).font(.system(size: buoyText + 1, weight: .heavy))
                Text(batteryBuoyWatt).font(.system(size: buoyText - 1, weight: .semibold))
            }
        }
    }

    private var batteryBuoyWatt: String {
        let charging = (data.charge ?? 0) > 0 && (data.discharge ?? 0) <= 0
        let discharging = (data.discharge ?? 0) > 0 && (data.charge ?? 0) <= 0
        if charging { return Fmt.watt(data.charge) }
        if discharging { return Fmt.watt(data.discharge) }
        return "0 W"
    }

    private var buoyGrid: some View {
        buoy {
            VStack(alignment: .trailing, spacing: 0) {
                Text("市电").font(.system(size: buoyText - 2, weight: .semibold)).opacity(0.85)
                Text(Fmt.watt(data.grid)).font(.system(size: buoyText, weight: .heavy))
                Text(gridStateText).font(.system(size: buoyText - 2, weight: .semibold)).opacity(0.85)
            }
        }
    }

    private var gridStateText: String {
        guard let g = data.grid else { return "--" }
        if abs(g) < 50 { return "正常" }
        return g > 0 ? "取电" : "馈电"
    }
}

/// 一个 Canvas 画完所有能流线：避免 8 个独立 Shape + blur 图层，滚动时开销显著降低。
/// 相位完全由外部时钟给出；只有 active 的线路才推进相位，无数据时线静止。
private struct FlowCanvas: View {
    let w: CGFloat, h: CGFloat
    let phase: Double
    let pv: Bool, load: Bool
    let battery: Bool, batteryReverse: Bool
    let grid: Bool, gridReverse: Bool

    var body: some View {
        Canvas { ctx, _ in
            let routes: [(FlowShape, Bool, Bool)] = [
                (.pv, pv, false),
                (.load, load, false),
                (.battery, battery, batteryReverse),
                (.grid, grid, gridReverse),
            ]
            for (route, active, reverse) in routes {
                let path = route.path(in: CGSize(width: w, height: h))
                // 底光常显，无数据时更暗但不消失
                ctx.stroke(path, with: .color(Color(hex: 0x41F4FF).opacity(active ? 0.24 : 0.07)),
                           lineWidth: max(5, w * 0.018))
                if active {
                    ctx.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [Color(hex: 0x78F8FF), Color(hex: 0xD9FFFF), Color(hex: 0x44E5FF)]),
                            startPoint: .zero, endPoint: CGPoint(x: w, y: h)
                        ),
                        style: StrokeStyle(
                            lineWidth: max(2.4, w * 0.010),
                            lineCap: .round,
                            // HA 原值 dasharray 22 58（约 1:2.6），光带短而离散，
                            // 这里加长到 44:30 让流动更连贯，避免"极慢/断续"观感
                            dash: [max(44, w * 0.30), max(30, w * 0.20)],
                            // HA: Forward = dashoffset 0→-1000（沿路径起点→终点流动），
                            // Reverse = 0→+1000。phase 是递增正值，故正向取负、反向取正。
                            dashPhase: reverse ? CGFloat(phase) : CGFloat(-phase)
                        )
                    )
                } else {
                    ctx.stroke(path, with: .color(Color(hex: 0x78F8FF).opacity(0.28)),
                               lineWidth: max(1.6, w * 0.007))
                }
            }
            let hub = CGPoint(x: w * (1010 / 1617), y: h * (640 / 971))
            let r = max(3, w * 0.006)
            ctx.fill(Path(ellipseIn: CGRect(x: hub.x - r, y: hub.y - r, width: r * 2, height: r * 2)),
                     with: .color(Palette.cyan.opacity(0.9)))
        }
    }
}

// MARK: - 能流路径（与 HA 面板 SVG 同源）

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
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: data.isNight ? data.weather.nightSymbol : data.weather.symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Palette.text)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("今日预计").foregroundStyle(Palette.dim)
                    Text(Fmt.kwh(data.forecastToday))
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    Text("剩余").foregroundStyle(Palette.dim)
                    Text(Fmt.kwh(data.forecastRemaining))
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Text(secondLine)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // 预测条嵌入天气背景，不加玻璃卡片
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .shadow(color: Color.black.opacity(0.55), radius: 3, y: 1)
    }

    private var secondLine: String {
        // 天气状态与昼夜解耦：夜间仍显示真实天气，不再把"多云"替换成"夜间"
        var parts: [String] = [data.weather.label]
        if let rain = data.rainSoonText { parts.append(rain) }
        if let t = data.forecastTomorrow { parts.append("明日预计 \(Fmt.kwh(t))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @Binding var haURL: String
    @Binding var haToken: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant 地址") {
                    TextField("http://www.example.com:8123", text: $haURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("建议填 DDNS 域名；IPv6 直连要写成 http://[地址]:8123")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("长期访问令牌") {
                    SecureField("eyJ0eXAiOiJKV1Qi...", text: $haToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("HA → 个人资料 → 安全 → 长期访问令牌 → 创建")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("保存并刷新") {
                        onSave()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
