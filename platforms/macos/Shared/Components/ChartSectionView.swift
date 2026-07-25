import SwiftUI

/// Chart sections for WidgetKit — **no GeometryReader**.
///
/// GeometryReader often resolves to 0×0 during WidgetKit snapshot/archive, so
/// pure SwiftUI Paths inside it draw nothing. We take an explicit height and use
/// `Canvas` / fixed frames instead.
struct ChartSectionView: View {
    let chartType: ChartType
    let title: String?
    let data: [ChartPoint]
    let size: CanvasSize
    /// Shrink charts when the tile is already overflowing so chrome stays visible.
    var heightScale: CGFloat = 1.0
    /// Debug-ish “bar · N points” line; off when overflowing to save space.
    var showPointCaption: Bool = true

    private var points: [ChartPoint] {
        let cap: Int
        switch size {
        case .sm: cap = 5
        case .md: cap = 8
        case .lg: cap = 12
        case .xl: cap = 20
        }
        return Array(data.prefix(cap))
    }

    private var chartHeight: CGFloat {
        // Keep in sync with ContentClip.chartPlotHeight.
        ContentClip.chartPlotHeight(for: size, scale: heightScale)
    }

    /// High-contrast plot color (accentColor is often invisible on dark widget chrome).
    static let plot = Color(red: 0.35, green: 0.62, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            if points.isEmpty {
                Text("No chart data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: chartHeight, alignment: .center)
            } else {
                Group {
                    switch chartType {
                    case .bar:
                        FixedBarChart(points: points, height: chartHeight, showLabels: size != .sm)
                    case .line:
                        FixedLineChart(points: points, height: chartHeight)
                    case .pie:
                        FixedPieChart(
                            points: points,
                            height: chartHeight,
                            showLegend: size == .lg || size == .xl
                        )
                    case .gauge:
                        FixedGaugeChart(points: points, height: chartHeight)
                    }
                }
                if showPointCaption {
                    Text("\(chartType.rawValue) · \(points.count) points")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Bar (fixed height, no GeometryReader)

private struct FixedBarChart: View {
    let points: [ChartPoint]
    let height: CGFloat
    let showLabels: Bool

    private var maxV: Double {
        max(points.map(\.value).max() ?? 1, 0.001)
    }

    private var plotHeight: CGFloat {
        showLabels ? height - 12 : height
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                    let ratio = CGFloat(pt.value / maxV)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(ChartSectionView.plot)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, plotHeight * ratio))
                }
            }
            .frame(height: plotHeight, alignment: .bottom)

            if showLabels {
                HStack(spacing: 3) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                        Text(pt.label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 10)
            }
        }
        .frame(height: height)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        )
    }
}

// MARK: - Line via Canvas (size provided by Canvas)

private struct FixedLineChart: View {
    let points: [ChartPoint]
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            guard points.count >= 1, size.width > 1, size.height > 1 else { return }

            let maxV = max(points.map(\.value).max() ?? 1, 0.001)
            let minV = points.map(\.value).min() ?? 0
            let span = max(maxV - minV, 0.001)
            let n = max(points.count - 1, 1)
            let inset: CGFloat = 4
            let w = size.width - inset * 2
            let h = size.height - inset * 2

            func pt(_ i: Int) -> CGPoint {
                let x = inset + w * CGFloat(i) / CGFloat(n)
                let y = inset + h * (1 - CGFloat((points[i].value - minV) / span))
                return CGPoint(x: x, y: y)
            }

            // Area
            var area = Path()
            area.move(to: CGPoint(x: pt(0).x, y: inset + h))
            for i in points.indices {
                area.addLine(to: pt(i))
            }
            area.addLine(to: CGPoint(x: pt(points.count - 1).x, y: inset + h))
            area.closeSubpath()
            context.fill(area, with: .color(Color(red: 0.35, green: 0.62, blue: 1.0).opacity(0.25)))

            // Line
            var line = Path()
            line.move(to: pt(0))
            for i in points.indices.dropFirst() {
                line.addLine(to: pt(i))
            }
            context.stroke(
                line,
                with: .color(Color(red: 0.35, green: 0.62, blue: 1.0)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            // Dots
            for i in points.indices {
                let p = pt(i)
                let r: CGFloat = 3.5
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.35, green: 0.62, blue: 1.0)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .frame(height: height)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        )
    }
}

// MARK: - Pie via Canvas

private struct FixedPieChart: View {
    let points: [ChartPoint]
    let height: CGFloat
    let showLegend: Bool

    private let palette: [Color] = [
        .blue, .cyan, .orange, .green, .purple, .pink, .yellow, .mint,
    ]

    var body: some View {
        HStack(spacing: 8) {
            Canvas { context, size in
                let total = max(points.map(\.value).reduce(0, +), 0.001)
                let side = min(size.width, size.height)
                let rect = CGRect(
                    x: (size.width - side) / 2,
                    y: (size.height - side) / 2,
                    width: side,
                    height: side
                )
                let c = CGPoint(x: rect.midX, y: rect.midY)
                let r = side / 2
                var start = Angle.degrees(-90)

                for (i, pt) in points.enumerated() {
                    let sweep = Angle.degrees(360 * pt.value / total)
                    let end = start + sweep
                    var path = Path()
                    path.move(to: c)
                    path.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(palette[i % palette.count]))
                    start = end
                }
            }
            .frame(width: height, height: height)

            if showLegend {
                VStack(alignment: .leading, spacing: 3) {
                    let total = max(points.map(\.value).reduce(0, +), 0.001)
                    ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(palette[i % palette.count])
                                .frame(width: 6, height: 6)
                            Text(pt.label)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(String(format: "%.0f%%", 100 * pt.value / total))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Gauge (no GeometryReader)

private struct FixedGaugeChart: View {
    let points: [ChartPoint]
    let height: CGFloat

    var body: some View {
        let value = points.first?.value ?? 0
        let maxV = max(points.map(\.value).max() ?? 1, 0.001)
        let fraction = min(max(value / maxV, 0), 1)

        VStack(alignment: .leading, spacing: 8) {
            // Fixed-width proportional bar using overlay + scaleEffect on leading align
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 12)
                Capsule()
                    .fill(Color.blue)
                    .frame(height: 12)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
            }
            .frame(height: 12)

            HStack {
                Text(points.first?.label ?? "Value")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(fmt(value)) / \(fmt(maxV))")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: height)
        .padding(.horizontal, 4)
    }

    private func fmt(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
