import SwiftUI
import AppKit

struct ListSectionView: View {
    let title: String?
    let items: [ListItem]
    let size: CanvasSize
    /// Total items before clip — used by footer overflow; kept for call-site API.
    var totalBeforeClip: Int? = nil
    /// Document section index for action deep links (nil = inert rows).
    var documentSectionIndex: Int? = nil
    var canvasId: String? = nil
    var interactionMode: CanvasActionInteractionMode = .inert
    /// Host detail: invoke instead of Link.
    var onItemAction: ((Int, ListItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(index: index, item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func isActionable(_ item: ListItem) -> Bool {
        guard let action = item.action else { return false }
        return action != .noop
    }

    @ViewBuilder
    private func row(index: Int, item: ListItem) -> some View {
        let content = rowContent(item)
        let actionable = isActionable(item)

        switch interactionMode {
        case .inert:
            content
        case .widgetLink:
            if actionable,
               size != .sm,
               let canvasId,
               let section = documentSectionIndex
            {
                Link(destination: CanvasActionURL.itemURL(
                    canvasId: canvasId,
                    section: section,
                    item: item,
                    itemIndex: index
                )) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        case .hostButton:
            if actionable {
                Button {
                    onItemAction?(index, item)
                } label: {
                    content
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            } else {
                content
            }
        }
    }

    private func rowContent(_ item: ListItem) -> some View {
        let showLinkStyle = isActionable(item)
            && interactionMode != .inert
            && !(interactionMode == .widgetLink && size == .sm)

        return HStack(alignment: .top, spacing: 6) {
            CanvasIcon.leading(name: item.icon, tone: item.tone, pointSize: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.primary)
                    .font(.caption.weight(StyleTokens.fontWeight(for: item.emphasis)))
                    .foregroundStyle(
                        showLinkStyle
                            ? Color.accentColor
                            : StyleTokens.foreground(tone: item.tone)
                    )
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
                    .background(
                        (StyleTokens.color(for: item.tone) ?? badgeColor(badge)).opacity(0.2),
                        in: Capsule()
                    )
                    .foregroundStyle(StyleTokens.color(for: item.tone) ?? badgeColor(badge))
                    .lineLimit(1)
            }
        }
    }

    private func badgeColor(_ badge: String) -> Color {
        let b = badge.uppercased()
        if b.contains("P1") || b.contains("CRIT") || b.contains("HIGH") { return .red }
        if b.contains("P2") || b.contains("MED") { return .orange }
        if b.contains("P3") || b.contains("LOW") { return .blue }
        return .secondary
    }
}
