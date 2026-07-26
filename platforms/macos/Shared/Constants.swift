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
    /// Previous canvas snapshots: `history/{id}/{entryId}.json` + `index.json`.
    static let historySubdir = "history"
    static let reloadRequestFileName = ".reload-request"
    /// MCP → host: request a PNG snapshot of a canvas.
    static let previewRequestFileName = ".preview-request"
    static let previewsSubdir = "previews"
    static let assetsSubdir = "assets"
    /// Matches Rust `MAX_IMAGE_PIXELS`.
    static let maxImagePixels: Int = 4_000_000
    /// Matches Rust `MAX_IMAGE_BYTES`.
    static let maxImageBytes: Int = 2 * 1024 * 1024
    static let sharesFileName = "shares.json"
    static let subscriptionsFileName = "subscriptions.json"
    static let cloudConfigFileName = "cloud-config.json"
    /// Matches Rust Keychain service (agent-canvas-core).
    static let editTokenKeychainService = "com.velox.agentcanvas.canvas-edit-token"
    /// User OAuth tokens (access/refresh) — separate from per-slug edit tokens.
    static let oauthKeychainService = "com.velox.agentcanvas.oauth"
    /// Exact redirect registered for the public OAuth client (PKCE).
    static let oauthRedirectURI = "agentcanvas://oauth/callback"
    static let oauthURLScheme = "agentcanvas"
    static let oauthCallbackHost = "oauth"
    static let oauthCallbackPath = "/callback"
    static let oauthClientIdEnvName = "AGENT_CANVAS_OAUTH_CLIENT_ID"
    static let oauthScopes = "openid profile email offline_access"
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
