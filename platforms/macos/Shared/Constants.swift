import Foundation
import WidgetKit

enum AgentCanvasConstants {
    static let appBundleId = "com.velox.agentcanvas"
    static let widgetBundleId = "com.velox.agentcanvas.widget"
    static let appGroupId = "group.com.velox.agentcanvas"
    /// Shared Velox data root: `~/.velox/canvas/` (MCP + host + widgets).
    static let veloxDirName = ".velox"
    static let canvasDirName = "canvas"
    static let canvasesSubdir = "canvases"
    static let reloadRequestFileName = ".reload-request"
    /// MCP → host: request a PNG snapshot of a canvas.
    static let previewRequestFileName = ".preview-request"
    static let previewsSubdir = "previews"
}

/// Size-first canvas address: `sm-one`, `md-two`, `lg-three`, `xl-one`, …
/// Keep in sync with Rust `CanvasId` / MCP tool docs.
enum CanvasAddress: String, CaseIterable, Identifiable, Codable {
    case smOne = "sm-one"
    case smTwo = "sm-two"
    case smThree = "sm-three"
    case mdOne = "md-one"
    case mdTwo = "md-two"
    case mdThree = "md-three"
    case lgOne = "lg-one"
    case lgTwo = "lg-two"
    case lgThree = "lg-three"
    case xlOne = "xl-one"
    case xlTwo = "xl-two"
    case xlThree = "xl-three"

    var id: String { rawValue }

    var size: CanvasSize {
        switch self {
        case .smOne, .smTwo, .smThree: return .sm
        case .mdOne, .mdTwo, .mdThree: return .md
        case .lgOne, .lgTwo, .lgThree: return .lg
        case .xlOne, .xlTwo, .xlThree: return .xl
        }
    }

    var slot: CanvasSlot {
        switch self {
        case .smOne, .mdOne, .lgOne, .xlOne: return .one
        case .smTwo, .mdTwo, .lgTwo, .xlTwo: return .two
        case .smThree, .mdThree, .lgThree, .xlThree: return .three
        }
    }

    var fileName: String { "\(rawValue).json" }

    /// WidgetKit kind — unique per size+slot so instances never thrash size meta.
    var widgetKind: String { "AgentCanvas.\(rawValue)" }

    /// Gallery title — ASCII hyphen so names search cleanly in Edit Widgets.
    var displayName: String {
        "\(size.galleryLabel) - \(slot.shortLabel)"
    }

    var galleryDescription: String {
        "Fixed \(size.galleryLabel.lowercased()) agent canvas (slot \(slot.shortLabel.lowercased())). "
            + "MCP id: \(rawValue)."
    }

    /// Single WidgetFamily — not multi-size.
    var widgetFamily: WidgetFamily {
        size.widgetFamily
    }

    static var allKinds: [String] {
        allCases.map(\.widgetKind)
    }
}

enum CanvasSize: String, CaseIterable {
    case sm, md, lg, xl

    var widgetFamily: WidgetFamily {
        switch self {
        case .sm: return .systemSmall
        case .md: return .systemMedium
        case .lg: return .systemLarge
        case .xl: return .systemExtraLarge
        }
    }

    var galleryLabel: String {
        switch self {
        case .sm: return "Small"
        case .md: return "Medium"
        case .lg: return "Large"
        case .xl: return "Extra Large"
        }
    }

    /// Hard max sections (aligned with Rust SizeBudget).
    var sectionCap: Int {
        switch self {
        case .sm: return 2
        case .md: return 4
        case .lg: return 6
        case .xl: return 8
        }
    }

    var listItemCap: Int { ContentClip.listItemCap(for: self) }
}

enum CanvasSlot: String, CaseIterable {
    case one, two, three

    var shortLabel: String {
        switch self {
        case .one: return "One"
        case .two: return "Two"
        case .three: return "Three"
        }
    }
}
