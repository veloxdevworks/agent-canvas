import Foundation
import CoreGraphics

/// Codable models for canvas schema v1.
/// Keep field names aligned with `schema/canvas.schema.json` and agent-canvas-core.

struct CanvasDocument: Codable, Equatable {
    var version: Int
    var updatedAt: Date?
    var title: String?
    var onOpen: CanvasAction?
    var sections: [CanvasSection]
    var detail: CanvasDetail?

    static let schemaVersion = 1

    static var empty: CanvasDocument {
        CanvasDocument(
            version: schemaVersion,
            updatedAt: Date(),
            title: nil,
            onOpen: nil,
            sections: [],
            detail: nil
        )
    }

    var isEmptyContent: Bool {
        sections.isEmpty && (title == nil || title?.isEmpty == true)
    }

    /// Sections shown in the expand detail window.
    var detailSections: [CanvasSection] {
        if let detail, !detail.sections.isEmpty {
            return detail.sections
        }
        return sections
    }

    /// Effective tile tap action (default expand).
    var resolvedOnOpen: CanvasAction {
        onOpen ?? .expand
    }
}

struct CanvasDetail: Codable, Equatable {
    var sections: [CanvasSection]
}

/// Declarative intent shared by document `onOpen` and per-item `action`.
enum CanvasAction: Codable, Equatable {
    case expand
    case url(String)
    case file(String)
    case noop

    private enum CodingKeys: String, CodingKey {
        case type, url, path
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "expand":
            self = .expand
        case "url":
            self = .url(try c.decode(String.self, forKey: .url))
        case "file":
            self = .file(try c.decode(String.self, forKey: .path))
        case "noop":
            self = .noop
        default:
            self = .noop
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .expand:
            try c.encode("expand", forKey: .type)
        case let .url(url):
            try c.encode("url", forKey: .type)
            try c.encode(url, forKey: .url)
        case let .file(path):
            try c.encode("file", forKey: .type)
            try c.encode(path, forKey: .path)
        case .noop:
            try c.encode("noop", forKey: .type)
        }
    }

    func validate(context: String = "action") throws {
        switch self {
        case .expand, .noop:
            return
        case let .url(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CanvasActionError.invalid("\(context).url: url is required")
            }
            guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() else {
                throw CanvasActionError.invalid("\(context).url: invalid URL")
            }
            guard ["http", "https", "mailto"].contains(scheme) else {
                throw CanvasActionError.invalid(
                    "\(context).url: scheme `\(scheme)` is not allowed (use http, https, or mailto)"
                )
            }
            if let user = parsed.user, !user.isEmpty {
                throw CanvasActionError.invalid("\(context).url: embedded credentials are not allowed")
            }
            if parsed.password != nil {
                throw CanvasActionError.invalid("\(context).url: embedded credentials are not allowed")
            }
        case let .file(path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CanvasActionError.invalid("\(context).file: path is required")
            }
            if trimmed.contains("\0") {
                throw CanvasActionError.invalid("\(context).file: path must not contain NUL")
            }
        }
    }
}

enum CanvasActionError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): return message
        }
    }
}

enum GroupDirection: String, Codable, Equatable {
    case row, column
}

enum GroupAlign: String, Codable, Equatable {
    case start, center, end, stretch
}

enum CanvasSection: Codable, Equatable {
    case header(text: String, subtitle: String?, tone: CanvasTone?, emphasis: CanvasEmphasis?, priority: Int?)
    case text(content: String, tone: CanvasTone?, emphasis: CanvasEmphasis?, priority: Int?)
    case metrics(items: [MetricItem], priority: Int?)
    case chart(chartType: ChartType, title: String?, data: [ChartPoint], priority: Int?)
    case list(title: String?, items: [ListItem], priority: Int?)
    case image(source: String, caption: String?, priority: Int?)
    case spacer(size: SpacerSize?, priority: Int?)
    case group(
        direction: GroupDirection,
        gap: SpacerSize?,
        align: GroupAlign?,
        children: [CanvasSection],
        weight: Int?,
        priority: Int?
    )
    case progress(label: String?, value: Double, max: Double?, tone: CanvasTone?, priority: Int?)
    case divider(priority: Int?)
    case keyValue(items: [KeyValueItem], priority: Int?)
    case badges(items: [BadgeItem], priority: Int?)
    case unknown(type: String)

    static func header(text: String, subtitle: String? = nil) -> CanvasSection {
        .header(text: text, subtitle: subtitle, tone: nil, emphasis: nil, priority: nil)
    }

    static func text(content: String) -> CanvasSection {
        .text(content: content, tone: nil, emphasis: nil, priority: nil)
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
        case .group: return "group"
        case .progress: return "progress"
        case .divider: return "divider"
        case .keyValue: return "keyValue"
        case .badges: return "badges"
        case .unknown(let t): return t
        }
    }

    /// Lower = more important (drop priority from LayoutSpec).
    var sortPriority: Int {
        let explicit: Int?
        switch self {
        case let .header(_, _, _, _, p),
             let .text(_, _, _, p),
             let .metrics(_, p),
             let .chart(_, _, _, p),
             let .list(_, _, p),
             let .image(_, _, p),
             let .spacer(_, p),
             let .group(_, _, _, _, _, p),
             let .progress(_, _, _, _, p),
             let .divider(p),
             let .keyValue(_, p),
             let .badges(_, p):
            explicit = p
        case .unknown:
            explicit = 100
        }
        if let explicit { return explicit }
        return LayoutSpec.dropPriority[typeName] ?? 100
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, subtitle, content, items, chartType, title, data, source, url, caption
        case size, priority, tone, emphasis, direction, gap, align, children, weight
        case label, value, max, key
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        let tone = try c.decodeIfPresent(CanvasTone.self, forKey: .tone)
        let emphasis = try c.decodeIfPresent(CanvasEmphasis.self, forKey: .emphasis)
        switch type {
        case "header":
            self = .header(
                text: try c.decode(String.self, forKey: .text),
                subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
                tone: tone,
                emphasis: emphasis,
                priority: priority
            )
        case "text":
            self = .text(
                content: try c.decode(String.self, forKey: .content),
                tone: tone,
                emphasis: emphasis,
                priority: priority
            )
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
        case "group":
            self = .group(
                direction: try c.decode(GroupDirection.self, forKey: .direction),
                gap: try c.decodeIfPresent(SpacerSize.self, forKey: .gap),
                align: try c.decodeIfPresent(GroupAlign.self, forKey: .align),
                children: try c.decode([CanvasSection].self, forKey: .children),
                weight: try c.decodeIfPresent(Int.self, forKey: .weight),
                priority: priority
            )
        case "progress":
            self = .progress(
                label: try c.decodeIfPresent(String.self, forKey: .label),
                value: try c.decode(Double.self, forKey: .value),
                max: try c.decodeIfPresent(Double.self, forKey: .max),
                tone: tone,
                priority: priority
            )
        case "divider":
            self = .divider(priority: priority)
        case "keyValue":
            self = .keyValue(items: try c.decode([KeyValueItem].self, forKey: .items), priority: priority)
        case "badges":
            self = .badges(items: try c.decode([BadgeItem].self, forKey: .items), priority: priority)
        default:
            self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .header(text, subtitle, tone, emphasis, priority):
            try c.encode("header", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(subtitle, forKey: .subtitle)
            try c.encodeIfPresent(tone, forKey: .tone)
            try c.encodeIfPresent(emphasis, forKey: .emphasis)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .text(content, tone, emphasis, priority):
            try c.encode("text", forKey: .type)
            try c.encode(content, forKey: .content)
            try c.encodeIfPresent(tone, forKey: .tone)
            try c.encodeIfPresent(emphasis, forKey: .emphasis)
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
        case let .group(direction, gap, align, children, weight, priority):
            try c.encode("group", forKey: .type)
            try c.encode(direction, forKey: .direction)
            try c.encodeIfPresent(gap, forKey: .gap)
            try c.encodeIfPresent(align, forKey: .align)
            try c.encode(children, forKey: .children)
            try c.encodeIfPresent(weight, forKey: .weight)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .progress(label, value, max, tone, priority):
            try c.encode("progress", forKey: .type)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(value, forKey: .value)
            try c.encodeIfPresent(max, forKey: .max)
            try c.encodeIfPresent(tone, forKey: .tone)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .divider(priority):
            try c.encode("divider", forKey: .type)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .keyValue(items, priority):
            try c.encode("keyValue", forKey: .type)
            try c.encode(items, forKey: .items)
            try c.encodeIfPresent(priority, forKey: .priority)
        case let .badges(items, priority):
            try c.encode("badges", forKey: .type)
            try c.encode(items, forKey: .items)
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
    var tone: CanvasTone?
    var emphasis: CanvasEmphasis?

    init(
        label: String,
        value: String,
        trend: String? = nil,
        tone: CanvasTone? = nil,
        emphasis: CanvasEmphasis? = nil
    ) {
        self.label = label
        self.value = value
        self.trend = trend
        self.tone = tone
        self.emphasis = emphasis
    }
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
    var action: CanvasAction?
    var tone: CanvasTone?
    var emphasis: CanvasEmphasis?

    init(
        primary: String,
        secondary: String? = nil,
        badge: String? = nil,
        action: CanvasAction? = nil,
        tone: CanvasTone? = nil,
        emphasis: CanvasEmphasis? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.badge = badge
        self.action = action
        self.tone = tone
        self.emphasis = emphasis
    }
}

struct KeyValueItem: Codable, Equatable {
    var key: String
    var value: String
    var tone: CanvasTone?
}

struct BadgeItem: Codable, Equatable {
    var text: String
    var tone: CanvasTone?
}

enum SpacerSize: String, Codable, Equatable {
    case sm, md, lg

    var gapPoints: CGFloat {
        switch self {
        case .sm: return 4
        case .md: return 8
        case .lg: return 12
        }
    }
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
