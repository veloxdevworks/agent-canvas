import SwiftUI
import WidgetKit

/// Widget surface: **top-leading viewport**, bottom/right may clip.
///
/// WidgetKit is not a normal layout engine: if the view’s *ideal* height exceeds
/// the offered tile, the host often **centers** the view and clips the **top**.
///
/// Fix:
/// 1. Re-pack sections against the **GeometryReader** size (true tile).
/// 2. Explicit `frame(width:height:)` so ideal == offered.
/// 3. Lists keep as many rows as remaining height allows.
struct CanvasView: View {
    let entry: CanvasEntry
    /// Host ImageRenderer / MCP preview — solid chrome instead of WidgetKit material.
    var isPreview: Bool = false

    private var size: CanvasSize { entry.address.size }

    private var edgeInset: CGFloat {
        ContentClip.edgeInset(for: size)
    }

    var body: some View {
        let surface = GeometryReader { geo in
            let clip = packedClip(tile: geo.size)
            Group {
                if entry.document.isEmptyContent || entry.isPlaceholder {
                    emptyState
                } else {
                    contentStack(clip: clip)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }

        if isPreview {
            surface
                .background {
                    RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
                        // Approximate macOS widget material for agent screenshots.
                        .fill(Color(red: 0.13, green: 0.13, blue: 0.14))
                }
                .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous))
        } else {
            surface
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
    }

    private var previewCornerRadius: CGFloat {
        switch size {
        case .sm, .md: return 22
        case .lg, .xl: return 24
        }
    }

    /// sm skips the bulky doc title so list rows get the height instead.
    private var showsDocumentTitle: Bool {
        guard size != .sm else { return false }
        guard let title = entry.document.title, !title.isEmpty else { return false }
        return !isRedundantTitle(title, sections: entry.document.sections)
    }

    /// Pack against the real offered size so sm/md lists get rows, not a full drop.
    private func packedClip(tile: CGSize) -> ContentClip.Result {
        let doc = entry.document
        let hasTitle = showsDocumentTitle
        let hasTimestamp = doc.updatedAt != nil
        let live = !entry.isPlaceholder

        // Prefer fitting everything first; only reserve overflow chrome when needed.
        var budget = ContentClip.contentBudget(
            displaySize: tile,
            size: size,
            hasTitle: hasTitle && live,
            hasTimestamp: hasTimestamp && live,
            reserveOverflowLine: false
        )
        var clip = ContentClip.apply(document: doc, size: size, maxHeight: budget)

        if clip.truncated {
            budget = ContentClip.contentBudget(
                displaySize: tile,
                size: size,
                hasTitle: hasTitle && live,
                hasTimestamp: hasTimestamp && live,
                reserveOverflowLine: true
            )
            clip = ContentClip.apply(document: doc, size: size, maxHeight: budget)
        }
        return clip
    }

    private func contentStack(clip: ContentClip.Result) -> some View {
        let showOverflow = !entry.isPlaceholder && clip.truncated

        return VStack(alignment: .leading, spacing: 5) {
            if showsDocumentTitle, let title = entry.document.title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(clip.shown.enumerated()), id: \.offset) { _, section in
                sectionView(section, clip: clip)
            }

            if showOverflow || entry.document.updatedAt != nil {
                Spacer(minLength: 4)
            }

            if showOverflow {
                Text(overflowCaption(clip))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let updated = entry.document.updatedAt {
                Text(lastUpdatedLabel(updated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.address.displayName)
                .font(.headline)
            Text("MCP id: \(entry.address.rawValue)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Drop content here with your agent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lastUpdatedLabel(_ date: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        // Widget timelines don't tick every second — avoid frozen "N seconds ago".
        if secs < 60 {
            return "Last updated just now"
        }
        let mins = secs / 60
        if mins < 60 {
            return "Last updated \(mins) \(mins == 1 ? "minute" : "minutes") ago"
        }
        let hours = mins / 60
        if hours < 48 {
            return "Last updated \(hours) \(hours == 1 ? "hour" : "hours") ago"
        }
        let days = hours / 24
        return "Last updated \(days) \(days == 1 ? "day" : "days") ago"
    }

    private func overflowCaption(_ clip: ContentClip.Result) -> String {
        // Prefer partial-list wording when we kept the section but not all rows.
        if clip.listItemsTotal > clip.listItemsShown, clip.listItemsShown > 0 {
            return "+\(clip.listItemsTotal - clip.listItemsShown) more in list"
        }
        if !clip.droppedTypes.isEmpty {
            let types = clip.droppedTypes.joined(separator: ", ")
            return "+\(clip.droppedTypes.count) more hidden (\(types))"
        }
        if clip.listItemsTotal > clip.listItemsShown {
            return "+\(clip.listItemsTotal - clip.listItemsShown) more in list"
        }
        return "Content clipped for \(size.rawValue)"
    }

    private func isRedundantTitle(_ title: String, sections: [CanvasSection]) -> Bool {
        if case let .header(text, _, _)? = sections.first {
            return title.localizedCaseInsensitiveContains(text)
                || text.localizedCaseInsensitiveContains(title)
        }
        return false
    }

    @ViewBuilder
    private func sectionView(_ section: CanvasSection, clip: ContentClip.Result) -> some View {
        switch section {
        case let .header(text, subtitle, _):
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .text(body, _):
            Text(body)
                .font(.caption)
                .lineLimit(size == .sm ? 2 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .metrics(items, _):
            MetricsSectionView(
                items: items,
                size: size,
                compact: size == .sm || size == .md
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .chart(chartType, title, data, _):
            ChartSectionView(
                chartType: chartType,
                title: title,
                data: data,
                size: size,
                // Absolute scale from ContentClip (size baseline + any shrink-to-fit).
                heightScale: clip.chartHeightScale,
                showPointCaption: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .list(title, items, _):
            ListSectionView(
                title: title,
                items: items,
                size: size,
                totalBeforeClip: clip.listItemsTotal > items.count ? clip.listItemsTotal : nil
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .image(_, caption, _):
            Label(caption ?? "Image", systemImage: "photo")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .spacer:
            Color.clear.frame(height: 4)
        case let .unknown(type):
            Text("Unsupported: \(type)")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }

}
