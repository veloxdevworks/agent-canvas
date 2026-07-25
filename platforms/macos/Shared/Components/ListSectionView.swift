import SwiftUI

struct ListSectionView: View {
    let title: String?
    let items: [ListItem]
    let size: CanvasSize
    /// Total items before clip — used by footer overflow; kept for call-site API.
    var totalBeforeClip: Int? = nil

    var body: some View {
        // Items are already height-packed by ContentClip — render all of them.
        // Remainder is the bottom footer ("+N more in list").
        VStack(alignment: .leading, spacing: 3) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.primary)
                            .font(.caption)
                            .lineLimit(1)
                        if let secondary = item.secondary, !secondary.isEmpty, size != .sm {
                            Text(secondary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let badge = item.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badgeColor(badge).opacity(0.2), in: Capsule())
                            .foregroundStyle(badgeColor(badge))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func badgeColor(_ badge: String) -> Color {
        let b = badge.uppercased()
        if b.contains("P1") || b.contains("CRIT") || b.contains("HIGH") { return .red }
        if b.contains("P2") || b.contains("MED") { return .orange }
        if b.contains("P3") || b.contains("LOW") { return .blue }
        return .secondary
    }
}
