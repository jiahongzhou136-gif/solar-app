import SwiftUI

/// 与 HA 面板 solar-app-card.js 的 ICONS 完全一致（原 SVG viewBox 0 0 24 24，描边风格）。
/// 用户已确认 HA 上是精心设计的图标，这里 1:1 复刻路径，不再使用 SF Symbols。
enum HAIcon: String {
    case solar, inverter, battery, grid, home

    var body: some View {
        ZStack {
            switch self {
            case .solar:    SolarIcon()
            case .inverter: InverterIcon()
            case .battery:  BatteryIcon()
            case .grid:     GridIcon()
            case .home:     HomeIcon()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 各图标 Shape

private struct SolarIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size
            let k = min(s.width, s.height) / 24
            let o = CGPoint(x: (s.width - 24 * k) / 2, y: (s.height - 24 * k) / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }

            ZStack {
                // 太阳圆 + 八条光芒
                Path { p in
                    p.addEllipse(in: CGRect(x: pt(5.8, 4.8).x, y: pt(5.8, 4.8).y,
                                            width: 4.4 * k, height: 4.4 * k))
                    let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                        (8, 1.5, 8, 3.5), (8, 10.5, 8, 12.5),
                        (2.5, 7, 4.5, 7), (11.5, 7, 13.5, 7),
                        (4.1, 3.1, 5.5, 4.5), (10.5, 9.5, 11.9, 10.9),
                        (11.9, 3.1, 10.5, 4.5), (5.5, 9.5, 4.1, 10.9),
                    ]
                    for a in segs {
                        p.move(to: pt(a.0, a.1)); p.addLine(to: pt(a.2, a.3))
                    }
                }
                // 光伏板
                Path { p in
                    p.move(to: pt(3, 15)); p.addLine(to: pt(13, 15))
                    p.addLine(to: pt(14.5, 21)); p.addLine(to: pt(1.5, 21))
                    p.closeSubpath()
                    let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                        (5.3, 15, 4.7, 21), (10.7, 15, 11.3, 21),
                        (2.2, 18, 13.8, 18), (8, 15, 8, 21),
                    ]
                    for a in segs {
                        p.move(to: pt(a.0, a.1)); p.addLine(to: pt(a.2, a.3))
                    }
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct InverterIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size
            let k = min(s.width, s.height) / 24
            let o = CGPoint(x: (s.width - 24 * k) / 2, y: (s.height - 24 * k) / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }

            ZStack {
                RoundedRectangle(cornerRadius: 3 * k, style: .continuous)
                    .path(in: CGRect(x: pt(4, 2.5).x, y: pt(4, 2.5).y, width: 16 * k, height: 19 * k))
                    .stroke(Color.white, lineWidth: 1.7)
                Path { p in
                    p.move(to: pt(8, 7)); p.addLine(to: pt(16, 7))
                    p.move(to: pt(8, 17)); p.addLine(to: pt(16, 17))
                    // 正弦波，对应原 SVG 的 c 曲线
                    p.move(to: pt(7.5, 12))
                    p.addCurve(to: pt(12, 12), control1: pt(9, 9.7), control2: pt(10.5, 9.7))
                    p.addCurve(to: pt(16.5, 12), control1: pt(13.5, 14.3), control2: pt(15, 14.3))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                Circle()
                    .path(in: CGRect(x: pt(7.3, 16.3).x, y: pt(7.3, 16.3).y, width: 1.4 * k, height: 1.4 * k))
                    .fill(Color.white)
            }
        }
    }
}

private struct BatteryIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size
            let k = min(s.width, s.height) / 24
            let o = CGPoint(x: (s.width - 24 * k) / 2, y: (s.height - 24 * k) / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }

            ZStack {
                RoundedRectangle(cornerRadius: 3 * k, style: .continuous)
                    .path(in: CGRect(x: pt(3, 6).x, y: pt(3, 6).y, width: 17 * k, height: 12 * k))
                    .stroke(Color.white, lineWidth: 1.7)
                Path { p in
                    p.move(to: pt(20, 10)); p.addLine(to: pt(21.5, 10))
                    p.addLine(to: pt(21.5, 14)); p.addLine(to: pt(20, 14))
                    p.move(to: pt(7, 12)); p.addLine(to: pt(16, 12))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct GridIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size
            let k = min(s.width, s.height) / 24
            let o = CGPoint(x: (s.width - 24 * k) / 2, y: (s.height - 24 * k) / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }

            Path { p in
                p.move(to: pt(12, 2)); p.addLine(to: pt(16.3, 8)); p.addLine(to: pt(7.7, 8)); p.closeSubpath()
                let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (9.2, 8, 6, 22), (14.8, 8, 18, 22),
                    (7.8, 12, 16.2, 12), (6.8, 17, 17.2, 17),
                    (4, 22, 20, 22),
                    (9.5, 8, 14.7, 17), (14.5, 8, 9.3, 17),
                ]
                for a in segs {
                    p.move(to: pt(a.0, a.1)); p.addLine(to: pt(a.2, a.3))
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct HomeIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size
            let k = min(s.width, s.height) / 24
            let o = CGPoint(x: (s.width - 24 * k) / 2, y: (s.height - 24 * k) / 2)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }

            Path { p in
                p.move(to: pt(3, 11.2)); p.addLine(to: pt(12, 3)); p.addLine(to: pt(21, 11.2))
                p.addLine(to: pt(21, 21)); p.addLine(to: pt(3, 21)); p.closeSubpath()
                p.move(to: pt(9, 21)); p.addLine(to: pt(9, 15))
                p.addLine(to: pt(15, 15)); p.addLine(to: pt(15, 21))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}
