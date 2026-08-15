import WidgetKit
import SwiftUI

/// Shared configuration factory — WidgetKit is picky about parameterized `Widget` types
/// in a `WidgetBundle`, so each definition gets a thin wrapper below.
enum CanvasWidgetFactory {
    static func configuration(for address: CanvasAddress) -> some WidgetConfiguration {
        StaticConfiguration(
            kind: address.widgetKind,
            provider: CanvasTimelineProvider(address: address)
        ) { entry in
            let url: URL = {
                #if os(iOS)
                if entry.document.isEmptyContent || entry.isPlaceholder {
                    return CanvasActionURL.howToURL()
                }
                return CanvasActionURL.canvasDetailURL(canvasId: address.rawValue)
                #else
                if entry.document.isEmptyContent || entry.isPlaceholder {
                    return CanvasActionURL.howToURL()
                }
                return CanvasActionURL.documentURL(canvasId: address.rawValue)
                #endif
            }()
            CanvasView(entry: entry, actionInteraction: .widgetLink)
                .widgetURL(url)
        }
        .configurationDisplayName(address.displayName)
        .description(address.galleryDescription)
        .supportedFamilies(CanvasAddress.allSupportedFamilies)
        // Use the full tile; system content margins shrink the offer and fight packing.
        .contentMarginsDisabled()
    }
}

struct OneWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .one) }
}

struct TwoWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .two) }
}

struct ThreeWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .three) }
}

struct FourWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .four) }
}

struct FiveWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .five) }
}

struct SixWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .six) }
}

struct SevenWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .seven) }
}

struct EightWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .eight) }
}

struct NineWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .nine) }
}

struct TenWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .ten) }
}

struct ElevenWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .eleven) }
}

struct TwelveWidget: Widget {
    var body: some WidgetConfiguration { CanvasWidgetFactory.configuration(for: .twelve) }
}
