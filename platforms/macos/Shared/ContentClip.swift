import Foundation
import CoreGraphics

/// Priority + height packing for WidgetKit.
///
/// Constants come from `LayoutSpec` (generated from Rust). Lists are **row-fit**.
enum ContentClip {
    struct Result: Equatable {
        var shown: [CanvasSection]
        /// Document section indices parallel to `shown` (for action deep links).
        var shownIndices: [Int]
        var droppedTypes: [String]
        var truncated: Bool
        var listItemsShown: Int
        var listItemsTotal: Int
        /// Applied to chart plots when packing had to shrink them to fit metrics/header.
        var chartHeightScale: CGFloat = 1.0
        /// Document has a cover — glance is full-bleed; sections unused on tile.
        var cover: Bool = false
    }

    static func imageHeight(for size: CanvasSize, height: ImageHeight?) -> CGFloat {
        let spec = LayoutSpec.size(size)
        switch height ?? .default {
        case .small: return spec.imageHeightSmall
        case .medium: return spec.imageHeightMedium
        case .large: return spec.imageHeightLarge
        }
    }

    static func listItemCap(for size: CanvasSize) -> Int {
        LayoutSpec.size(size).listItemCap
    }

    static func maxCharts(for size: CanvasSize) -> Int {
        LayoutSpec.size(size).maxCharts
    }

    static func edgeInset(for size: CanvasSize) -> CGFloat {
        LayoutSpec.size(size).edgeInset
    }

    static func chartPlotHeight(for size: CanvasSize, scale: CGFloat = 1.0) -> CGFloat {
        let base = LayoutSpec.size(size).chartPlotHeight
        return max(22, base * scale)
    }

    static func chartHeightScale(for size: CanvasSize) -> CGFloat {
        LayoutSpec.size(size).chartHeightScale
    }

    static func listRowHeight(for size: CanvasSize) -> CGFloat {
        LayoutSpec.size(size).listRowHeight
    }

    static func listTitleHeight(_ title: String?) -> CGFloat {
        guard let title, !title.isEmpty else { return 0 }
        return LayoutSpec.size(.md).listTitleHeight
    }

    static func listSectionHeight(
        title: String?,
        rows: Int,
        size: CanvasSize
    ) -> CGFloat {
        let spec = LayoutSpec.size(size)
        let titleH = (title?.isEmpty == false) ? spec.listTitleHeight : 0
        let rowH = spec.listRowHeight
        let blocks = (titleH > 0 ? 1 : 0) + rows
        let spacing: CGFloat = blocks > 1 ? CGFloat(blocks - 1) * 3 : 0
        return titleH + CGFloat(rows) * rowH + spacing
    }

    /// Compositional height — containers derive from children.
    static func estimatedHeight(
        _ section: CanvasSection,
        size: CanvasSize,
        chartScale: CGFloat? = nil
    ) -> CGFloat {
        let spec = LayoutSpec.size(size)
        switch section {
        case let .header(_, subtitle, _, _, _):
            return subtitle == nil ? spec.headerHeightNoSubtitle : spec.headerHeightWithSubtitle
        case .metrics:
            return spec.metricsHeight
        case let .chart(_, title, _, _):
            let scale = chartScale ?? spec.chartHeightScale
            let plot = chartPlotHeight(for: size, scale: scale)
            let titleH: CGFloat = (title?.isEmpty == false) ? 12 : 0
            let gap: CGFloat = titleH > 0 ? 2 : 0
            return titleH + gap + plot
        case let .list(title, items, _):
            return listSectionHeight(title: title, rows: items.count, size: size)
        case .text:
            return spec.textHeight
        case let .image(_, _, height, _):
            return imageHeight(for: size, height: height)
        case let .spacer(spacerSize, _):
            return spacerSize?.gapPoints ?? spec.spacerHeight
        case let .progress(_, _, _, _, _):
            return spec.progressHeight
        case .divider:
            return spec.dividerHeight
        case let .keyValue(items, _):
            let n = CGFloat(max(items.count, 1))
            return n * spec.keyValueRowHeight + max(n - 1, 0) * 2
        case .badges:
            return spec.badgesHeight
        case let .group(direction, gap, _, children, _, _):
            let heights = children.map { estimatedHeight($0, size: size) }
            let gapPts = gap?.gapPoints ?? 4
            switch direction {
            case .row:
                return heights.max() ?? 0
            case .column:
                let sum = heights.reduce(0, +)
                let gaps = children.count > 1 ? CGFloat(children.count - 1) * gapPts : 0
                return sum + gaps
            }
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
        let spec = LayoutSpec.size(size)
        let gap = spacing ?? (size == .md ? 4 : 6)
        var h: CGFloat = 0
        if hasTitle {
            h += spec.titleChromeHeight + gap
        }
        var footerBlocks = 0
        if showOverflow { h += spec.overflowLineHeight; footerBlocks += 1 }
        if hasTimestamp { h += spec.timestampHeight; footerBlocks += 1 }
        if footerBlocks > 1 { h += 3 }
        if footerBlocks > 0 { h += 3 }
        return h
    }

    static func defaultTileHeight(for size: CanvasSize) -> CGFloat {
        LayoutSpec.size(size).tileHeight
    }

    static func defaultTileSize(for size: CanvasSize) -> CGSize {
        let s = LayoutSpec.size(size)
        return CGSize(width: s.tileWidth, height: s.tileHeight)
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
        if document.cover != nil {
            return Result(
                shown: [],
                shownIndices: [],
                droppedTypes: [],
                truncated: false,
                listItemsShown: 0,
                listItemsTotal: 0,
                chartHeightScale: 1.0,
                cover: true
            )
        }

        let spec = LayoutSpec.size(size)
        let budget = maxHeight ?? defaultContentHeight(for: size)
        let candidates = prioritizedCandidates(document: document, size: size)
        let spacing = spec.sectionSpacing

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

            let clipped: CanvasSection
            if (size == .sm || size == .md), case let .header(text, subtitle, tone, emphasis, priority) = section {
                let keepSub: String? = {
                    guard size == .md, let subtitle, !subtitle.isEmpty else { return nil }
                    return subtitle.count <= 36 ? subtitle : nil
                }()
                clipped = .header(
                    text: text,
                    subtitle: size == .sm ? nil : keepSub,
                    tone: tone,
                    emphasis: emphasis,
                    priority: priority
                )
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
        var orderedIndices: [Int] = []
        var dropped: [String] = []
        var minChartScale: CGFloat? = nil
        for (i, section) in document.sections.enumerated() {
            if let shown = packed[i] {
                ordered.append(shown)
                orderedIndices.append(i)
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
            shownIndices: orderedIndices,
            droppedTypes: dropped,
            truncated: truncated,
            listItemsShown: listShown,
            listItemsTotal: listTotal,
            chartHeightScale: minChartScale ?? chartHeightScale(for: size)
        )
    }

    private struct ChartFit {
        var section: CanvasSection
        var height: CGFloat
        var scale: CGFloat
    }

    private static func fitChart(
        _ section: CanvasSection,
        size: CanvasSize,
        maxHeight: CGFloat
    ) -> ChartFit? {
        guard case let .chart(t, title, data, priority) = section else { return nil }
        let base = chartHeightScale(for: size)
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

    private struct ListFit {
        var section: CanvasSection
        var height: CGFloat
        var rows: Int
    }

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

        if let w = with, let wo = without {
            return wo.rows > w.rows ? wo : w
        }
        return with ?? without
    }

    private static func prioritizedCandidates(
        document: CanvasDocument,
        size: CanvasSize
    ) -> [(Int, CanvasSection)] {
        let sections = document.sections
        var charts = 0
        let chartCap = maxCharts(for: size)

        func packRank(_ section: CanvasSection) -> Int {
            LayoutSpec.packRank[section.typeName] ?? 7
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
        let spec = LayoutSpec.size(size)
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
            let lim = size == .sm ? 2 : min(4, spec.maxMetrics)
            return .metrics(items: Array(items.prefix(lim)), priority: priority)
        case let .text(content, tone, emphasis, priority):
            let lim = spec.maxTextChars
            if content.count <= lim { return section }
            let end = content.index(content.startIndex, offsetBy: lim)
            return .text(
                content: String(content[..<end]) + "…",
                tone: tone,
                emphasis: emphasis,
                priority: priority
            )
        case let .list(title, items, priority):
            let lim = listItemCap(for: size)
            return .list(title: title, items: Array(items.prefix(lim)), priority: priority)
        default:
            return section
        }
    }
}
