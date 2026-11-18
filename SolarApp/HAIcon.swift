import SwiftUI

/// 与 HA 面板 solar-app-card.js 的 ICONS 完全一致（原 SVG viewBox 0 0 24 24，描边风格）。
/// 用户已确认 HA 上是精心设计的图标，这里 1:1 复刻路径，不再使用 SF Symbols。
enum HAIcon: String {
    case solar, inverter, battery, grid, home

    @ViewBuilder var body: some View {
        switch self {
        case .solar:    SolarIcon()
        case .inverter: InverterIcon()
        case .battery:  BatteryIcon()
        case .grid:     GridIcon()
        case .home:     HomeIcon()
        }
    }
}

/// 24×24 坐标系换算，避免在 ViewBuilder 闭包里声明局部变量
private struct IconGeom {
    let size: CGSize
    var k: CGFloat { min(size.width, size.height) / 24 }
    var ox: CGFloat { (size.width - 24 * k) / 2 }
    var oy: CGFloat { (size.height - 24 * k) / 2 }
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * k, y: oy + y * k)
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: ox + x * k, y: oy + y * k, width: w * k, height: h * k)
    }
}

private struct SolarIcon: View {
    var body: some View {
        GeometryReader { geo in
            SolarShape(size: geo.size)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct SolarShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.addEllipse(in: g.rect(5.8, 4.8, 4.4, 4.4))
        let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (8, 1.5, 8, 3.5), (8, 10.5, 8, 12.5),
            (2.5, 7, 4.5, 7), (11.5, 7, 13.5, 7),
            (4.1, 3.1, 5.5, 4.5), (10.5, 9.5, 11.9, 10.9),
            (11.9, 3.1, 10.5, 4.5), (5.5, 9.5, 4.1, 10.9),
            (3, 15, 13, 15), (13, 15, 14.5, 21),
            (14.5, 21, 1.5, 21), (1.5, 21, 3, 15),
            (5.3, 15, 4.7, 21), (10.7, 15, 11.3, 21),
            (2.2, 18, 13.8, 18), (8, 15, 8, 21),
        ]
        for a in segs {
            p.move(to: g.pt(a.0, a.1)); p.addLine(to: g.pt(a.2, a.3))
        }
        return p
    }
}

private struct InverterIcon: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                InverterBoxShape(size: geo.size)
                    .stroke(Color.white, lineWidth: 1.7)
                InverterWaveShape(size: geo.size)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
        }
    }
}

private struct InverterBoxShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.addRoundedRect(in: g.rect(4, 2.5, 16, 19), cornerSize: CGSize(width: 3 * g.k, height: 3 * g.k), style: .continuous)
        return p
    }
}

private struct InverterWaveShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.move(to: g.pt(8, 7)); p.addLine(to: g.pt(16, 7))
        p.move(to: g.pt(8, 17)); p.addLine(to: g.pt(16, 17))
        p.move(to: g.pt(7.5, 12))
        p.addCurve(to: g.pt(12, 12), control1: g.pt(9, 9.7), control2: g.pt(10.5, 9.7))
        p.addCurve(to: g.pt(16.5, 12), control1: g.pt(13.5, 14.3), control2: g.pt(15, 14.3))
        p.addEllipse(in: g.rect(7.3, 16.3, 1.4, 1.4))
        return p
    }
}

private struct BatteryIcon: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                BatteryBoxShape(size: geo.size)
                    .stroke(Color.white, lineWidth: 1.7)
                BatteryTerminalShape(size: geo.size)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct BatteryBoxShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.addRoundedRect(in: g.rect(3, 6, 17, 12), cornerSize: CGSize(width: 3 * g.k, height: 3 * g.k), style: .continuous)
        return p
    }
}

private struct BatteryTerminalShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.move(to: g.pt(20, 10)); p.addLine(to: g.pt(21.5, 10))
        p.addLine(to: g.pt(21.5, 14)); p.addLine(to: g.pt(20, 14))
        p.move(to: g.pt(7, 12)); p.addLine(to: g.pt(16, 12))
        return p
    }
}

private struct GridIcon: View {
    var body: some View {
        GeometryReader { geo in
            GridShape(size: geo.size)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct GridShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.move(to: g.pt(12, 2)); p.addLine(to: g.pt(16.3, 8)); p.addLine(to: g.pt(7.7, 8)); p.closeSubpath()
        let segs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (9.2, 8, 6, 22), (14.8, 8, 18, 22),
            (7.8, 12, 16.2, 12), (6.8, 17, 17.2, 17),
            (4, 22, 20, 22),
            (9.5, 8, 14.7, 17), (14.5, 8, 9.3, 17),
        ]
        for a in segs {
            p.move(to: g.pt(a.0, a.1)); p.addLine(to: g.pt(a.2, a.3))
        }
        return p
    }
}

private struct HomeIcon: View {
    var body: some View {
        GeometryReader { geo in
            HomeShape(size: geo.size)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct HomeShape: Shape {
    let size: CGSize
    func path(in r: CGRect) -> Path {
        let g = IconGeom(size: size)
        var p = Path()
        p.move(to: g.pt(3, 11.2)); p.addLine(to: g.pt(12, 3)); p.addLine(to: g.pt(21, 11.2))
        p.addLine(to: g.pt(21, 21)); p.addLine(to: g.pt(3, 21)); p.closeSubpath()
        p.move(to: g.pt(9, 21)); p.addLine(to: g.pt(9, 15))
        p.addLine(to: g.pt(15, 15)); p.addLine(to: g.pt(15, 21))
        return p
    }
}
