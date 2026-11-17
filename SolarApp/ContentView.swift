import SwiftUI
import UIKit

// MARK: - 设计系统
//
// 圆角是同心层级，不是所有卡片都用屏幕半径。
// iPhone 17 Pro 屏幕圆角 62pt（ScreenCorners 实测），卡片距边 14pt，
// 外层容器 = 62 − 14 = 48pt，弧线与屏幕平行同心；内层按体量递减。

enum Design {
    // 圆角
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

    // 间距
    static let gap: CGFloat = 12
    static let cardPadH: CGFloat = 16
    static let cardPadV: CGFloat = 14
    static let cardMinHeight: CGFloat = 84

    // 动效
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.84)
    static let snappy = Animation.snappy(duration: 0.34)
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)

    // 字体阶梯
    static let heroNumber = Font.system(size: 50, weight: .bold, design: .rounded)
    static let cardNumber = Font.system(size: 23, weight: .semibold, design: .rounded)
    static let label = Font.system(size: 11, weight: .medium)
    static let unit = Font.system(size: 10, weight: .medium)
    static let footnote = Font.system(size: 10, weight: .regular)
}

enum Theme {
    static let bg     = Color(red: 0.067, green: 0.094, blue: 0.125) // #111820
    static let accent = Color(red: 0.961, green: 0.651, blue: 0.137) // #F5A623
    static let dim    = Color(red: 0.604, green: 0.643, blue: 0.698)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let hairline = Color.white.opacity(0.08)
}

// MARK: - 格式化

private func kw(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.2f", v / 1000)
}
private func kwh(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f", v)
}
private func pct(_ v: Double?) -> String {
    guard let v else { return "--" }
    return "\(Int(v.rounded()))%"
}
private func clock(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

// MARK: - 主界面

struct ContentView: View {
    @AppStorage("ha_url")    private var haURL: String = SolarConfig.defaultBaseURL
    @AppStorage("ha_token")  private var haToken: String = ""
    @AppStorage("panel_url") private var panelURL: String = SolarConfig.defaultPanelURL

    @State private var data: SolarData?
    @State private var error: String?
    @State private var loading = false
    @State private var showSettings = false
    @State private var appeared = false

    private var skeleton: Bool { loading && data == nil }

    var body: some View {
        NavigationStack {
            ZStack {
                // 底色 + 极淡橙色光晕：磨砂卡需要有东西可透，纯色底是没有质感的
                Theme.bg.ignoresSafeArea()
                RadialGradient(
                    colors: [Theme.accent.opacity(0.10), .clear],
                    center: .init(x: 0.85, y: 0.12),
                    startRadius: 0,
                    endRadius: 460
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: Design.gap) {
                        heroCard
                        metricsGrid
                        footerCards
                    }
                    .padding(.horizontal, Design.screenPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    await load()
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("光伏监控")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationCornerRadius(Design.containerRadius)
                    .presentationDragIndicator(.visible)
            }
            .task { await autoRefresh() }
            .onAppear {
                guard !appeared else { return }
                withAnimation(Design.spring) { appeared = true }
            }
        }
    }

    // MARK: 全景卡

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Image("Lumina")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 236)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("实时功率")
                        .font(Design.label)
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer()
                    if let data {
                        Text("\(clock(data.updatedAt)) 更新")
                            .font(Design.footnote)
                            .foregroundStyle(.white.opacity(0.52))
                            .contentTransition(.numericText())
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(kw(data?.pv))
                        .font(Design.heroNumber)
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text("kW")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: Design.containerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.containerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 10)
        .animation(Design.snappy, value: data)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    // MARK: 指标

    private var metricsGrid: some View {
        let ratio: Double? = {
            guard let d = data?.daily, let f = data?.forecast, f > 0 else { return nil }
            return min(max(d / f, 0), 1.5)
        }()

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Design.gap),
                GridItem(.flexible(), spacing: Design.gap)
            ],
            spacing: Design.gap
        ) {
            MetricCard(
                title: "今日发电",
                value: kwh(data?.daily),
                unit: "kWh",
                icon: "sun.max.fill",
                progress: ratio.map { min($0, 1) },
                footnote: ratio.map { "预测完成 \(Int(($0 * 100).rounded()))%" }
            )
            MetricCard(
                title: "今日预测",
                value: kwh(data?.forecast),
                unit: "kWh",
                icon: "chart.line.uptrend.xyaxis"
            )
            MetricCard(
                title: "电池 SOC",
                value: pct(data?.soc),
                unit: "",
                icon: "battery.75percent",
                progress: data?.soc.map { min(max($0 / 100, 0), 1) }
            )
            MetricCard(
                title: "当前负载",
                value: kw(data?.load),
                unit: "kW",
                icon: "house.fill"
            )
        }
        .redacted(reason: skeleton ? .placeholder : [])
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(Design.spring.delay(0.06), value: appeared)
        .animation(Design.snappy, value: data)
    }

    // MARK: 底部

    private var footerCards: some View {
        VStack(spacing: Design.gap) {
            if let error {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.danger)
                    Text(error)
                        .font(Design.footnote)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Design.cardPadH)
                .padding(.vertical, Design.cardPadV)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                        .strokeBorder(Theme.danger.opacity(0.24), lineWidth: 1)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            HStack {
                Label("累计发电", systemImage: "bolt.fill")
                    .font(Design.label)
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text("\(kwh(data?.total)) kWh")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Design.cardPadH)
            .padding(.vertical, Design.cardPadV)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .redacted(reason: skeleton ? .placeholder : [])

            if let url = URL(string: panelURL), !panelURL.isEmpty {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 13))
                        Text("打开完整面板")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Design.cardPadH)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                            .fill(Theme.accent.opacity(0.10))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1)
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(Design.spring.delay(0.12), value: appeared)
    }

    // MARK: 数据

    private func autoRefresh() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let fresh = try await HAClient(baseURL: haURL, token: haToken).fetchSolar()
            withAnimation(Design.snappy) {
                data = fresh
                error = nil
            }
        } catch {
            withAnimation(Design.snappy) {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - 指标卡

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    var progress: Double? = nil
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(title)
                    .font(Design.label)
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Design.cardNumber)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(Design.unit)
                        .foregroundStyle(Theme.dim)
                }
            }

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.accent.opacity(0.55), Theme.accent],
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
                    .font(Design.footnote)
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: Design.cardMinHeight, alignment: .topLeading)
        .padding(.horizontal, Design.cardPadH - 2)
        .padding(.vertical, Design.cardPadV)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
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

// MARK: - 设置

struct SettingsView: View {
    @AppStorage("ha_url")    private var haURL: String = SolarConfig.defaultBaseURL
    @AppStorage("ha_token")  private var haToken: String = ""
    @AppStorage("panel_url") private var panelURL: String = SolarConfig.defaultPanelURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant") {
                    TextField("http://192.168.1.100:8123", text: $haURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("长期访问令牌", text: $haToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("面板地址") {
                    TextField("http://.../solar-board/solar", text: $panelURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Text("令牌在 HA → 个人资料 → 安全 → 长期访问令牌 里创建。")
                    Text("外网访问时地址换成 http://[IPv6]:8123，方括号不能少。")
                }
                .font(.footnote)
                .foregroundStyle(Theme.dim)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
