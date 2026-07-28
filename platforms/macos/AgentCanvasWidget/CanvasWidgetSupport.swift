import WidgetKit
import SwiftUI

/// Shared configuration factory — WidgetKit is picky about parameterized `Widget` types
/// in a `WidgetBundle`, so each address gets a thin wrapper below.
enum CanvasWidgetFactory {
    static func configuration(for address: CanvasAddress) -> some WidgetConfiguration {
        StaticConfiguration(
            kind: address.widgetKind,
            provider: CanvasTimelineProvider(address: address)
        ) { entry in
            let url: URL =
                (entry.document.isEmptyContent || entry.isPlaceholder)
                ? CanvasActionURL.howToURL()
                : CanvasActionURL.documentURL(canvasId: address.rawValue)
            CanvasView(entry: entry, actionInteraction: .widgetLink)
                .widgetURL(url)
        }
        .configurationDisplayName(address.displayName)
        .description(address.galleryDescription)
        .supportedFamilies([address.widgetFamily])
        // Use the full tile; system content margins shrink the offer and fight packing.
        .contentMarginsDisabled()
    }
}

// MARK: - Small

struct SmOneWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .smOne) }
}
struct SmTwoWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .smTwo) }
}
struct SmThreeWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .smThree) }
}

// MARK: - Medium

struct MdOneWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .mdOne) }
}
struct MdTwoWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .mdTwo) }
}
struct MdThreeWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .mdThree) }
}

// MARK: - Large

struct LgOneWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .lgOne) }
}
struct LgTwoWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .lgTwo) }
}
struct LgThreeWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .lgThree) }
}

// MARK: - Extra Large

struct XlOneWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .xlOne) }
}
struct XlTwoWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .xlTwo) }
}
struct XlThreeWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .xlThree) }
}
