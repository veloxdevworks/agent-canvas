import Foundation
import CoreGraphics

/// Priority + height packing for WidgetKit.
///
/// Lists are **row-fit**: maximize how many real items fit in the remaining
/// height. Prefer more rows over chrome (list titles). Footer reports "+N more".
enum ContentClip {
    struct Result {
        var shown: [CanvasSection]
        var droppedTypes: [String]
        var truncated: Bool
        var listItemsShown: Int
        var listItemsTotal: Int
        /// Applied to chart plots when packing had to shrink them to fit metrics/header.
        var chartHeightScale: CGFloat = 1.0
    }

    static func listItemCap(for size: CanvasSize) -> Int {
        switch size {
        case .sm: return 5
        case .md: return 6
        case .lg: return 10
        case .xl: return 14
        }
    }

    static func maxCharts(for size: CanvasSize) -> Int {
        switch size {
        case .sm: return 0
        case .md: return 1
        case .lg, .xl: return 2
        }
    }

    static func edgeInset(for size: CanvasSize) -> CGFloat {
        switch size {
        case .sm: return 12
        case .md: return 10 // reclaim 4pt for content on the short medium tile
        case .lg, .xl: return 14
        }
    }

    /// Default chart plot height (before adaptive shrink). Keep in sync with ChartSectionView.
    static func chartPlotHeight(for size: CanvasSize, scale: CGFloat = 1.0) -> CGFloat {
        let base: CGFloat
        switch size {
        case .sm: base = 36
        case .md: base = 40
        case .lg: base = 72
        case .xl: base = 84
        }
        // Floor keeps a readable sparkline on medium when sharing space with metrics.
        return max(22, base * scale)
    }

    /// CanvasView uses heightScale < 1 on smaller tiles; estimates must match.
    static func chartHeightScale(for size: CanvasSize) -> CGFloat {
        switch size {
        case .sm: return 0.9
        case .md: return 0.85
        case .lg, .xl: return 1.0
        }
    }

    /// Row heights tuned to actual ListSectionView (sm = single line).
    static func listRowHeight(for size: CanvasSize) -> CGFloat {
        switch size {
        case .sm: return 16
        case .md: return 26
        case .lg, .xl: return 28
        }
    }

    static func listTitleHeight(_ title: String?) -> CGFloat {
        guard let title, !title.isEmpty else { return 0 }
        return 14
    }

    static func listSectionHeight(
        title: String?,
        rows: Int,
        size: CanvasSize
    ) -> CGFloat {
        let titleH = listTitleHeight(title)
        let rowH = listRowHeight(for: size)
        let blocks = (titleH > 0 ? 1 : 0) + rows
        let spacing: CGFloat = blocks > 1 ? CGFloat(blocks - 1) * 3 : 0
        return titleH + CGFloat(rows) * rowH + spacing
    }

    static func estimatedHeight(
        _ section: CanvasSection,
        size: CanvasSize,
        chartScale: CGFloat? = nil
    ) -> CGFloat {
        switch section {
        case let .header(_, subtitle, _):
            // sm often has no subtitle — keep estimates tight.
            if size == .sm { return subtitle == nil ? 16 : 24 }
            // md: compact two-line header (price + change).
            if size == .md { return subtitle == nil ? 16 : 26 }
            return subtitle == nil ? 18 : 28
        case .metrics:
            // Matches MetricsSectionView compact (sm/md) vs full (lg/xl).
            return size == .sm || size == .md ? 26 : 48
        case let .chart(_, title, _, _):
            // CanvasView always sets showPointCaption: false — do not reserve caption.
            let scale = chartScale ?? chartHeightScale(for: size)
            let plot = chartPlotHeight(for: size, scale: scale)
            let titleH: CGFloat = (title?.isEmpty == false) ? 12 : 0
            let gap: CGFloat = titleH > 0 ? 2 : 0
            return titleH + gap + plot
        case let .list(title, items, _):
            return listSectionHeight(title: title, rows: items.count, size: size)
        case .text:
            return size == .sm ? 26 : 34
        case .image:
            return 16
        case .spacer:
            return 4
        case .unknown:
            return 12
        }
    }

    static func chromeHeight(
        hasTitle: Bool,
        showOverflow: Bool,
        hasTimestamp: Bool,
        size: CanvasSize = .md,
        spacing: CGFloat? = nil
    ) -> CGFloat {
        let gap = spacing ?? (size == .md ? 4 : 6)
        var h: CGFloat = 0
        if hasTitle {
            // sm/md use slightly tighter headline chrome
            h += (size == .sm || size == .md ? 16 : 18) + gap
        }
        var footerBlocks = 0
        if showOverflow { h += 12; footerBlocks += 1 }
        if hasTimestamp { h += 11; footerBlocks += 1 }
        if footerBlocks > 1 { h += 3 }
        if footerBlocks > 0 { h += 3 }
        return h
    }

    static func defaultTileHeight(for size: CanvasSize) -> CGFloat {
        defaultTileSize(for: size).height
    }

    /// Approximate macOS WidgetKit desktop tile sizes for packing + PNG previews.
    static func defaultTileSize(for size: CanvasSize) -> CGSize {
        switch size {
        case .sm: return CGSize(width: 170, height: 170)
        case .md: return CGSize(width: 364, height: 170)
        case .lg: return CGSize(width: 364, height: 382)
        case .xl: return CGSize(width: 748, height: 382)
        }
    }

    static func defaultContentHeight(for size: CanvasSize) -> CGFloat {
        contentBudget(
            displaySize: CGSize(width: 0, height: defaultTileHeight(for: size)),
            size: size,
            hasTitle: true,
            hasTimestamp: true,
            reserveOverflowLine: true
        )
    }

    static func contentBudget(
        displaySize: CGSize,
        size: CanvasSize,
        hasTitle: Bool,
        hasTimestamp: Bool,
        reserveOverflowLine: Bool = true
    ) -> CGFloat {
        let tileH = displaySize.height > 1
            ? displaySize.height
            : defaultTileHeight(for: size)
        let inset = edgeInset(for: size) * 2
        let chrome = chromeHeight(
            hasTitle: hasTitle,
            showOverflow: reserveOverflowLine,
            hasTimestamp: hasTimestamp,
            size: size
        )
        return max(48, tileH - inset - chrome)
    }

    static func apply(
        document: CanvasDocument,
        size: CanvasSize,
        maxHeight: CGFloat? = nil
    ) -> Result {
        let budget = maxHeight ?? defaultContentHeight(for: size)
        // Pack by type priority (metrics before chart) so charts shrink into remainder
        // instead of crowding out glance metrics. Display order stays document order.
        let candidates = prioritizedCandidates(document: document, size: size)
        let spacing: CGFloat = size == .md ? 4 : 5

        var packed: [Int: CanvasSection] = [:]
        var chartScales: [Int: CGFloat] = [:]
        var used: CGFloat = 0
        var listShown = 0
        var listTotal = 0

        for (index, section) in candidates {
            if packed[index] != nil { continue }
            let gap = packed.isEmpty ? 0 : spacing
            let remaining = budget - used - gap
            if remaining < 8 { break }

            if case let .list(title, items, priority) = section {
                listTotal = max(listTotal, items.count)
                // sm: never spend height on "Queue" — rows only.
                let effectiveTitle = size == .sm ? nil : title
                if let fit = fitList(
                    title: effectiveTitle,
                    items: items,
                    priority: priority,
                    size: size,
                    maxHeight: remaining
                ) {
                    packed[index] = fit.section
                    used += gap + fit.height
                    listShown = max(listShown, fit.rows)
                }
                continue
            }

            // sm/md: keep header primary line; subtitle is optional density.
            let clipped: CanvasSection
            if (size == .sm || size == .md), case let .header(text, subtitle, priority) = section {
                // Keep subtitle on md when it looks short (change %); drop only if huge.
                let keepSub: String? = {
                    guard size == .md, let subtitle, !subtitle.isEmpty else { return size == .md ? subtitle : nil }
                    return subtitle.count <= 36 ? subtitle : nil
                }()
                clipped = .header(text: text, subtitle: size == .sm ? nil : keepSub, priority: priority)
            } else {
                clipped = clipNonList(section, size: size)
            }

            if case .chart = clipped {
                if let fit = fitChart(clipped, size: size, maxHeight: remaining) {
                    packed[index] = fit.section
                    chartScales[index] = fit.scale
                    used += gap + fit.height
                }
                continue
            }

            let h = estimatedHeight(clipped, size: size)
            if h > remaining { continue }
            packed[index] = clipped
            used += gap + h
        }

        // Retry any skipped lists with leftover space.
        if used < budget {
            for (index, section) in document.sections.enumerated() {
                guard packed[index] == nil else { continue }
                guard case let .list(title, items, priority) = section else { continue }
                let gap = packed.isEmpty ? 0 : spacing
                let remaining = budget - used - gap
                listTotal = max(listTotal, items.count)
                let effectiveTitle = size == .sm ? nil : title
                if let fit = fitList(
                    title: effectiveTitle,
                    items: items,
                    priority: priority,
                    size: size,
                    maxHeight: remaining
                ) {
                    packed[index] = fit.section
                    used += gap + fit.height
                    listShown = max(listShown, fit.rows)
                }
            }
        }

        // Last chance: shrink a skipped chart into leftover height.
        if used < budget {
            for (index, section) in document.sections.enumerated() {
                guard packed[index] == nil else { continue }
                guard case .chart = section else { continue }
                let gap = packed.isEmpty ? 0 : spacing
                let remaining = budget - used - gap
                let clipped = clipNonList(section, size: size)
                if let fit = fitChart(clipped, size: size, maxHeight: remaining) {
                    packed[index] = fit.section
                    chartScales[index] = fit.scale
                    used += gap + fit.height
                }
            }
        }

        // Force ≥1 real row rather than dropping the list section.
        if listShown == 0 {
            for (index, section) in document.sections.enumerated() {
                guard case let .list(title, items, priority) = section else { continue }
                guard let first = items.first else { continue }
                listTotal = max(listTotal, items.count)
                packed[index] = .list(
                    title: size == .sm ? nil : title,
                    items: [first],
                    priority: priority
                )
                listShown = 1
                break
            }
        }

        if packed.isEmpty, let first = document.sections.first {
            packed[0] = clipNonList(first, size: size)
        }

        var ordered: [CanvasSection] = []
        var dropped: [String] = []
        var minChartScale: CGFloat? = nil
        for (i, section) in document.sections.enumerated() {
            if let shown = packed[i] {
                ordered.append(shown)
                if let s = chartScales[i] {
                    minChartScale = min(minChartScale ?? s, s)
                }
            } else {
                dropped.append(section.typeName)
                if case let .list(_, items, _) = section {
                    listTotal = max(listTotal, items.count)
                }
            }
        }

        let truncated = !dropped.isEmpty || listTotal > listShown
        return Result(
            shown: ordered,
            droppedTypes: dropped,
            truncated: truncated,
            listItemsShown: listShown,
            listItemsTotal: listTotal,
            // Absolute scale for ChartSectionView (includes size baseline).
            chartHeightScale: minChartScale ?? chartHeightScale(for: size)
        )
    }

    // MARK: - Chart fitting

    private struct ChartFit {
        var section: CanvasSection
        var height: CGFloat
        var scale: CGFloat
    }

    /// Prefer full chart; shrink plot (and drop chart title) into remaining height
    /// rather than dropping metrics.
    private static func fitChart(
        _ section: CanvasSection,
        size: CanvasSize,
        maxHeight: CGFloat
    ) -> ChartFit? {
        guard case let .chart(t, title, data, priority) = section else { return nil }
        let base = chartHeightScale(for: size)
        // Largest first; then untitled variants if still too tall.
        let scales: [CGFloat] = [base, base * 0.85, base * 0.7, base * 0.55, 0.5, 0.4]
        let variants: [CanvasSection] = [
            .chart(chartType: t, title: title, data: data, priority: priority),
            .chart(chartType: t, title: nil, data: data, priority: priority),
        ]
        for variant in variants {
            for scale in scales {
                let h = estimatedHeight(variant, size: size, chartScale: scale)
                if h <= maxHeight {
                    return ChartFit(section: variant, height: h, scale: scale)
                }
            }
        }
        return nil
    }

    // MARK: - List fitting

    private struct ListFit {
        var section: CanvasSection
        var height: CGFloat
        var rows: Int
    }

    /// Maximize rows. Prefer more items over keeping the section title.
    private static func fitList(
        title: String?,
        items: [ListItem],
        priority: Int?,
        size: CanvasSize,
        maxHeight: CGFloat
    ) -> ListFit? {
        guard !items.isEmpty else { return nil }
        let cap = min(listItemCap(for: size), items.count)

        func best(for sectionTitle: String?) -> ListFit? {
            var bestRows = 0
            var bestH: CGFloat = 0
            for rows in 1...cap {
                let h = listSectionHeight(title: sectionTitle, rows: rows, size: size)
                if h <= maxHeight {
                    bestRows = rows
                    bestH = h
                } else {
                    break
                }
            }
            guard bestRows > 0 else { return nil }
            return ListFit(
                section: .list(
                    title: sectionTitle,
                    items: Array(items.prefix(bestRows)),
                    priority: priority
                ),
                height: bestH,
                rows: bestRows
            )
        }

        let without = best(for: nil)
        let with = title != nil ? best(for: title) : nil

        // More rows always wins; title only if it doesn't cost a row.
        if let w = with, let wo = without {
            return wo.rows > w.rows ? wo : w
        }
        return with ?? without
    }

    // MARK: - Order

    private static func prioritizedCandidates(
        document: CanvasDocument,
        size: CanvasSize
    ) -> [(Int, CanvasSection)] {
        let sections = document.sections
        var charts = 0
        let chartCap = maxCharts(for: size)

        // Pack order ≠ display order: keep glance metrics before charts so charts
        // shrink into the remainder instead of consuming the whole medium tile.
        func packRank(_ section: CanvasSection) -> Int {
            switch section {
            case .header: return 0
            case .metrics: return 1
            case .list: return 2
            case .chart: return 3
            case .text: return 4
            case .image: return 5
            case .spacer: return 6
            case .unknown: return 7
            }
        }

        var indexed = sections.enumerated().map { ($0.offset, $0.element) }
        indexed.sort { a, b in
            let ra = packRank(a.1)
            let rb = packRank(b.1)
            if ra != rb { return ra < rb }
            return a.0 < b.0
        }

        var result: [(Int, CanvasSection)] = []
        for (i, section) in indexed {
            if case .chart = section {
                if charts >= chartCap { continue }
                charts += 1
            }
            result.append((i, section))
        }
        return result
    }

    private static func clipNonList(_ section: CanvasSection, size: CanvasSize) -> CanvasSection {
        switch section {
        case let .chart(t, title, data, priority):
            let lim: Int
            switch size {
            case .sm: lim = 5
            case .md: lim = 8
            case .lg: lim = 12
            case .xl: lim = 16
            }
            return .chart(
                chartType: t,
                title: title,
                data: Array(data.prefix(lim)),
                priority: priority
            )
        case let .metrics(items, priority):
            let lim = size == .sm ? 2 : 4
            return .metrics(items: Array(items.prefix(lim)), priority: priority)
        case let .text(content, priority):
            let lim: Int
            switch size {
            case .sm: lim = 80
            case .md: lim = 160
            case .lg: lim = 320
            case .xl: lim = 480
            }
            if content.count <= lim { return section }
            let end = content.index(content.startIndex, offsetBy: lim)
            return .text(content: String(content[..<end]) + "…", priority: priority)
        case let .list(title, items, priority):
            let lim = listItemCap(for: size)
            return .list(title: title, items: Array(items.prefix(lim)), priority: priority)
        default:
            return section
        }
    }
}
