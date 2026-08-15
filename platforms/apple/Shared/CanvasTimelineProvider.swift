import WidgetKit
import Foundation
import CoreGraphics

struct CanvasTimelineProvider: TimelineProvider {
    let address: CanvasAddress

    func placeholder(in context: Context) -> CanvasEntry {
        makeEntry(
            document: .empty,
            isPlaceholder: true,
            recordRender: false,
            displaySize: context.displaySize,
            family: context.family
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CanvasEntry) -> Void) {
        let doc = CanvasStorage.load(address: address)
        completion(
            makeEntry(
                document: doc,
                isPlaceholder: false,
                recordRender: false,
                displaySize: context.displaySize,
                family: context.family
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CanvasEntry>) -> Void) {
        let doc = CanvasStorage.load(address: address)
        let entry = makeEntry(
            document: doc,
            isPlaceholder: false,
            recordRender: true,
            displaySize: context.displaySize,
            family: context.family
        )
        #if os(iOS)
        // Opportunistic self-refresh when the host app is not open (~45 min).
        let next = Calendar.current.date(byAdding: .minute, value: 45, to: Date())
            ?? Date().addingTimeInterval(45 * 60)
        #else
        // Mac host forces reloads; long fallback is fine.
        let next = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
            ?? Date().addingTimeInterval(3600)
        #endif
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry(
        document doc: CanvasDocument,
        isPlaceholder: Bool,
        recordRender: Bool,
        displaySize: CGSize,
        family: WidgetFamily
    ) -> CanvasEntry {
        let size = CanvasSize(widgetFamily: family) ?? .defaultBudget
        let hasTitle = (doc.title?.isEmpty == false)
        let hasTimestamp = doc.updatedAt != nil

        // Use the real offered height so packing matches the tile.
        let tile = displaySize.height > 1
            ? displaySize
            : CGSize(
                width: 0,
                height: ContentClip.defaultTileHeight(for: size)
            )

        // Prefer fitting everything first; only reserve overflow chrome when needed.
        var budget = ContentClip.contentBudget(
            displaySize: tile,
            size: size,
            hasTitle: hasTitle && !isPlaceholder,
            hasTimestamp: hasTimestamp && !isPlaceholder,
            reserveOverflowLine: false
        )
        var clip = ContentClip.apply(document: doc, size: size, maxHeight: budget)

        if clip.truncated {
            budget = ContentClip.contentBudget(
                displaySize: tile,
                size: size,
                hasTitle: hasTitle && !isPlaceholder,
                hasTimestamp: hasTimestamp && !isPlaceholder,
                reserveOverflowLine: true
            )
            clip = ContentClip.apply(document: doc, size: size, maxHeight: budget)
        }

        if recordRender, !doc.isEmptyContent {
            let report = LastRenderReport(
                canvas: address.rawValue,
                size: size.rawValue,
                truncated: clip.truncated,
                shownSectionCount: clip.shown.count,
                droppedSectionCount: clip.droppedTypes.count,
                droppedTypes: clip.droppedTypes,
                listItemsShown: clip.listItemsShown,
                listItemsTotal: clip.listItemsTotal,
                updatedAt: Date()
            )
            CanvasStorage.writeLastRender(report, address: address, size: size)
        }

        return CanvasEntry(
            date: Date(),
            address: address,
            size: size,
            document: doc,
            isPlaceholder: isPlaceholder,
            clip: clip,
            displaySize: tile
        )
    }
}
