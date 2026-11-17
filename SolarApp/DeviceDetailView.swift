import SwiftUI

// MARK: - 设备详情

struct DeviceDetailView: View {
    let kind: DeviceKind
    let client: HAClient

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DeviceDetail?
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var page = 0

    var body: some View {
        ZStack {
            backdrop

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if isLoading && detail == nil {
                        loadingBlock
                    } else if let errorText {
                        errorBlock(errorText)
                    } else if let detail {
                        if detail.sections.count > 1 {
                            tabBar(detail.sections)
                                .padding(.bottom, 2)
                        }

                        if let section = currentSection(detail) {
                            fieldCard(section)
                        }

                        if !detail.cells.isEmpty {
                            cellCard(detail.cells)
                        }

                        if let note = detail.note {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.sub)
                                .lineSpacing(3)
                        }

                        Text("数据来自 HA 实体 · 每 2 秒同步 · 下拉刷新")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.sub)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, Design.padH)
                .padding(.bottom, 34)
            }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .task { await loadLoop() }
        .animation(Design.snappy, value: detail)
    }

    private func currentSection(_ d: DeviceDetail) -> DetailSection? {
        guard !d.sections.isEmpty else { return nil }
        let index = min(max(page, 0), d.sections.count - 1)
        return d.sections[index]
    }

    // MARK: 背景（给玻璃提供可折射的内容）

    private var backdrop: some View {
        ZStack {
            Color(hex: 0x050D15)

            LinearGradient(
                colors: [Color(hex: 0x0E2A42), Color(hex: 0x081824), Color(hex: 0x040B12)],
                startPoint: .topLeading,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(hex: 0x2BA9C8).opacity(0.34), .clear],
                center: UnitPoint(x: 0.86, y: 0.06),
                startRadius: 8,
                endRadius: 460
            )

            RadialGradient(
                colors: [Color(hex: 0x1E5E8C).opacity(0.28), .clear],
                center: UnitPoint(x: 0.10, y: 0.62),
                startRadius: 8,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.kicker)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Color(hex: 0x7FD8FF))
                Text(kind.title)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(kind.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.rowLabel)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .modifier(GlassCircle())
        }
        .padding(.top, 8)
    }

    // MARK: 视图切换（电池两页）

    private func tabBar(_ sections: [DetailSection]) -> some View {
        HStack(spacing: 9) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                let active = index == min(max(page, 0), sections.count - 1)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Design.snappy) { page = index }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(active ? Color(hex: 0x0A2639) : Color(hex: 0xDCECF8))
                        Text(subtitle(for: section.title))
                            .font(.system(size: 9.5))
                            .foregroundStyle(active ? Color(hex: 0x38566B) : Palette.rowLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
                                .fill(Color(hex: 0xEBF6FF).opacity(0.94))
                        } else {
                            RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        }
                    }
                }
                .buttonStyle(CardPressStyle())
            }
        }
    }

    private func subtitle(for title: String) -> String {
        title == "BMS 数据" ? "SOC · 单体 · 安全" : "输出 · 温度 · Bus1"
    }

    // MARK: 字段（单列）

    private func fieldCard(_ section: DetailSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.bottom, 4)

            ForEach(Array(section.fields.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    Text(item.0)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.rowLabel)
                    Spacer(minLength: 8)
                    Text(item.1)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    if index < section.fields.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    // MARK: 单体电压

    private func cellCard(_ cells: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("单体电压")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                if let maxV = cells.max(), let minV = cells.min() {
                    Text(String(format: "压差 %.3f V", maxV - minV))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.rowLabel)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(Array(cells.enumerated()), id: \.offset) { idx, v in
                    VStack(spacing: 2) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.sub)
                        Text(String(format: "%.3f", v))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .modifier(CellChip())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    // MARK: 状态块

    private var loadingBlock: some View {
        HStack(spacing: 9) {
            ProgressView().tint(Palette.text)
            Text("正在读取…")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sub)
            Spacer()
        }
        .padding(16)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("读取失败")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.danger)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0xD8B4B4))
            Text("检查 HA 地址、令牌，或下拉重试")
                .font(.system(size: 10))
                .foregroundStyle(Palette.sub)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    // MARK: 取数

    /// 与源数据同频：Modbus 6 段 × 1.2s throttle ≈ 7.2s 一轮，2 秒轮询足以捕捉变化
    @MainActor
    private func loadLoop() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await client.fetchDetail(kind)
            detail = fresh
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 条件修饰器

enum AnyViewModifier {
    struct Empty: ViewModifier {
        func body(content: Content) -> some View { content }
    }

    struct Glass: ViewModifier {
        let radius: CGFloat
        func body(content: Content) -> some View {
            content.modifier(GlassCard(radius: radius))
        }
    }

    static var empty: Empty { Empty() }
    static func glass(_ radius: CGFloat) -> Glass { Glass(radius: radius) }
}

// MARK: - 单体电压格

struct CellChip: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .clear.tint(Color.white.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: Design.chipRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.chipRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        } else {
            content
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: Design.chipRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.chipRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        }
    }
}
