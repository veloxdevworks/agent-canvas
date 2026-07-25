import Foundation

/// Codable models for canvas schema v1.
/// Keep field names aligned with `schema/canvas.schema.json` and agent-canvas-core.

struct CanvasDocument: Codable, Equatable {
    var version: Int
    var updatedAt: Date?
    var title: String?
    var sections: [CanvasSection]

    static let schemaVersion = 1

    static var empty: CanvasDocument {
        CanvasDocument(version: schemaVersion, updatedAt: Date(), title: nil, sections: [])
    }

    var isEmptyContent: Bool {
        sections.isEmpty && (title == nil || title?.isEmpty == true)
    }
}

enum CanvasSection: Codable, Equatable {
    case header(text: String, subtitle: String?, priority: Int?)
    case text(content: String, priority: Int?)
    case metrics(items: [MetricItem], priority: Int?)
    case chart(chartType: ChartType, title: String?, data: [ChartPoint], priority: Int?)
    case list(title: String?, items: [ListItem], priority: Int?)
    case image(source: String, caption: String?, priority: Int?)
    case spacer(size: SpacerSize?, priority: Int?)
    case unknown(type: String)

    // Convenience constructors (default priority nil) for host/demo seed code.
    static func header(text: String, subtitle: String? = nil) -> CanvasSection {
        .header(text: text, subtitle: subtitle, priority: nil)
    }

    static func text(content: String) -> CanvasSection {
        .text(content: content, priority: nil)
    }

    static func metrics(items: [MetricItem]) -> CanvasSection {
        .metrics(items: items, priority: nil)
    }

    static func chart(chartType: ChartType, title: String?, data: [ChartPoint]) -> CanvasSection {
        .chart(chartType: chartType, title: title, data: data, priority: nil)
    }

    static func list(title: String?, items: [ListItem]) -> CanvasSection {
        .list(title: title, items: items, priority: nil)
    }

    static func image(source: String, caption: String?) -> CanvasSection {
        .image(source: source, caption: caption, priority: nil)
    }

    static func spacer(size: SpacerSize? = nil) -> CanvasSection {
        .spacer(size: size, priority: nil)
    }

    var typeName: String {
        switch self {
        case .header: return "header"
        case .text: return "text"
        case .metrics: return "metrics"
        case .chart: return "chart"
        case .list: return "list"
        case .image: return "image"
        case .spacer: return "spacer"
        case .unknown(let t): return t
        }
    }

    /// Lower = more important. Explicit priority wins; else type default.
    var sortPriority: Int {
        let explicit: Int?
        switch self {
        case let .header(_, _, p),
             let .text(_, p),
             let .metrics(_, p),
             let .chart(_, _, _, p),
             let .list(_, _, p),
             let .image(_, _, p),
             let .spacer(_, p):
            explicit = p
        case .unknown:
            explicit = 100
        }
        if let explicit { return explicit }
        switch self {
        case .header: return 10
        case .metrics: return 20
        case .chart: return 30
        case .list: return 40
        case .text: return 50
        case .image: return 60
        case .spacer: return 70
        case .unknown: return 100
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, subtitle, content, items, chartType, title, data, source, url, caption, size, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        switch type {
        case "header":
            self = .header(
                text: try c.decode(String.self, forKey: .text),
                subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
                priority: priority
            )
        case "text":
            self = .text(content: try c.decode(String.self, forKey: .content), priority: priority)
        case "metrics":
            self = .metrics(items: try c.decode([MetricItem].self, forKey: .items), priority: priority)
        case "chart":
            self = .chart(
                chartType: try c.decode(ChartType.self, forKey: .chartType),
                title: try c.decodeIfPresent(String.self, forKey: .title),
                data: try c.decode([ChartPoint].self, forKey: .data),
                priority: priority
            )
        case "list":
            self = .list(
                title: try c.decodeIfPresent(String.self, forKey: .title),
                items: try c.decode([ListItem].self, forKey: .items),
                priority: priority
            )
        case "image":
            let source = try c.decodeIfPresent(String.self, forKey: .source)
                ?? c.decode(String.self, forKey: .url)
            self = .image(
                source: source,
                caption: try c.decodeIfPresent(String.self, forKey: .caption),
                priority: priority
            )
        case "spacer":
            self = .spacer(size: try c.decodeIfPresent(SpacerSize.self, forKey: .size), priority: priority)
        default:
            self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .header(text, subtitle, priority):
            try c.encode("header", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .text(content, priority):
            try c.encode("text", forKey: .type)
            try c.encode(content, forKey: .content)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .metrics(items, priority):
            try c.encode("metrics", forKey: .type)
            try c.encode(items, forKey: .items)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .chart(chartType, title, data, priority):
            try c.encode("chart", forKey: .type)
            try c.encode(chartType, forKey: .chartType)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(data, forKey: .data)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .list(title, items, priority):
            try c.encode("list", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(items, forKey: .items)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .image(source, caption, priority):
            try c.encode("image", forKey: .type)
            try c.encode(source, forKey: .source)
            try c.encodeIfPresent(caption, forKey: .caption)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .spacer(size, priority):
            try c.encode("spacer", forKey: .type)
            try c.encodeIfPresent(size, forKey: .size)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .unknown(type):
            try c.encode(type, forKey: .type)
        }
    }
}

struct MetricItem: Codable, Equatable {
    var label: String
    var value: String
    var trend: String?
}

enum ChartType: String, Codable, Equatable {
    case bar, line, pie, gauge
}

struct ChartPoint: Codable, Equatable {
    var label: String
    var value: Double
}

struct ListItem: Codable, Equatable {
    var primary: String
    var secondary: String?
    var badge: String?
}

enum SpacerSize: String, Codable, Equatable {
    case sm, md, lg
}

/// Written after each widget timeline build (agents read via MCP get_canvas).
struct LastRenderReport: Codable, Equatable {
    var canvas: String
    var size: String
    var truncated: Bool
    var shownSectionCount: Int
    var droppedSectionCount: Int
    var droppedTypes: [String]
    var listItemsShown: Int
    var listItemsTotal: Int
    var updatedAt: Date
}
