import SwiftUI

// MARK: - 设备详情

struct DeviceDetailView: View {
    let kind: DeviceKind
    let client: HAClient

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DeviceDetail?
    @State private var errorText: String?
    @State private var isLoading = true

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
                        fieldGrid(detail.fields)

                        if !detail.cells.isEmpty {
                            cellSection(detail.cells)
                        }

                        if let note = detail.note {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: 0x8FA9BD))
                                .lineSpacing(3)
                        }

                        Text("数据来自 HA 实体 · 下拉刷新")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0x7F97AA))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, Design.padH)
                .padding(.bottom, 30)
            }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .task { await loadLoop() }
        .animation(Design.snappy, value: detail)
    }

    // MARK: 背景

    private var backdrop: some View {
        ZStack {
            Palette.bg
            LinearGradient(
                colors: [
                    Color(hex: 0x0D2236),
                    Color(hex: 0x081824),
                    Color(hex: 0x050D15),
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0x1D5C7A).opacity(0.35), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        .foregroundStyle(Color(hex: 0xA9C2D6))
                }
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .modifier(GlassCircle())
            }
        }
        .padding(.top, 6)
    }

    // MARK: 字段

    private func fieldGrid(_ fields: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("实时运行")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 18),
                          GridItem(.flexible(), spacing: 18)],
                spacing: 0
            ) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.0)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0xA9C2D6))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.1)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    // MARK: 单体电压

    private func cellSection(_ cells: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("单体电压")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                if let maxV = cells.max(), let minV = cells.min() {
                    Text(String(format: "压差 %.3f V", maxV - minV))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xA9C2D6))
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4),
                spacing: 5
            ) {
                ForEach(Array(cells.enumerated()), id: \.offset) { idx, v in
                    VStack(spacing: 2) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0x8FA9BD))
                        Text(String(format: "%.3f", v))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
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
                .foregroundStyle(Color(hex: 0xFF9B9B))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(hex: 0xD8B4B4))
            Text("检查 HA 地址、令牌，或下拉重试")
                .font(.system(size: 9.5))
                .foregroundStyle(Color(hex: 0x8FA9BD))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCard(radius: Design.rowRadius))
    }

    // MARK: 取数

    @MainActor
    private func loadLoop() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.fetchDetail(kind)
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
