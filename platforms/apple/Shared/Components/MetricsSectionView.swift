import SwiftUI

struct MetricsSectionView: View {
    let items: [MetricItem]
    let size: CanvasSize
    /// Two-line cells (value+trend / label) instead of three — less top-crop risk.
    var compact: Bool = false

    private var visible: [MetricItem] {
        Array(items.prefix(size == .sm ? 2 : 4))
    }

    var body: some View {
        HStack(alignment: .top, spacing: size == .sm ? 6 : 10) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                if compact {
                    compactCell(item)
                } else {
                    fullCell(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fullCell(_ item: MetricItem) -> some View {
        let valueWeight: Font.Weight = item.emphasis == .subtle ? .medium : .bold
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                CanvasIcon.leading(name: item.icon, tone: item.tone, pointSize: size == .sm ? 11 : 13)
                Text(item.value)
                    .font(size == .sm ? .subheadline.weight(valueWeight) : .title3.weight(valueWeight))
                    .foregroundStyle(StyleTokens.foreground(tone: item.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
            }
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let trend = item.trend, !trend.isEmpty {
                Text(trend)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(StyleTokens.color(for: item.tone) ?? trendColor(trend))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// value + trend on one line, label under — shorter block for md / overflow.
    private func compactCell(_ item: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                CanvasIcon.leading(name: item.icon, tone: item.tone, pointSize: 11)
                Text(item.value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(StyleTokens.foreground(tone: item.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
                if let trend = item.trend, !trend.isEmpty {
                    Text(trend)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(StyleTokens.color(for: item.tone) ?? trendColor(trend))
                        .lineLimit(1)
                }
            }
            Text(item.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func trendColor(_ trend: String) -> Color {
        let t = trend.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("+") || t.lowercased().contains("up") {
            return .green
        }
        if t.hasPrefix("-") || t.lowercased().contains("down") {
            return .orange
        }
        return .secondary
    }
}
