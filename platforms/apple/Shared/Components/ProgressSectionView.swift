import SwiftUI

struct ProgressSectionView: View {
    let label: String?
    let value: Double
    let maximum: Double?
    let tone: CanvasTone?
    let size: CanvasSize

    private var fraction: Double {
        let m = maximum ?? 1.0
        guard m > 0, value.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, value / m))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(StyleTokens.foreground(tone: tone, default: .accentColor))
                        .frame(width: Swift.max(4, geo.size.width * fraction))
                }
            }
            .frame(height: size == .sm ? 6 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
