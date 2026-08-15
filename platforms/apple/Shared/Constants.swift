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
    /// Host snapshot of WidgetCenter placements for MCP density budgeting.
    static let placedFamiliesFileName = "placed-families.json"
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
    /// Platform-seeded public OAuth client (no secret; PKCE S256).
    static let oauthClientId = "velox-agent-canvas"
    static let oauthScopes = "openid profile email offline_access canvas:read canvas:write"
}

/// Compiled canvas identity: `one` / `two` / `three`.
/// Size is chosen when the user places the widget — not baked into the id.
/// Keep in sync with Rust `CanvasId` / MCP tool docs.
enum CanvasAddress: String, CaseIterable, Identifiable, Codable {
    case one
    case two
    case three

    var id: String { rawValue }

    var slot: CanvasSlot {
        switch self {
        case .one: return .one
        case .two: return .two
        case .three: return .three
        }
    }

    var fileName: String { "\(rawValue).json" }

    /// WidgetKit kind — unique per definition; each kind supports all four families.
    var widgetKind: String { "AgentCanvas.\(rawValue)" }

    /// Gallery title — definition name only (user picks size when placing).
    var displayName: String { slot.shortLabel }

    var galleryDescription: String {
        #if os(iOS)
        "Agent canvas \(displayName). Pick a size when you add it. Id: \(rawValue). iPhone does not offer Extra Large."
        #else
        "Agent canvas \(displayName). Pick a size when you add it. MCP id: \(rawValue)."
        #endif
    }

    static var allSupportedFamilies: [WidgetFamily] {
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
    }

    static var allKinds: [String] {
        allCases.map(\.widgetKind)
    }

    /// Legacy size-baked filenames for one-release alias reads.
    var legacyFileNames: [String] {
        CanvasSize.allCases.map { "\($0.rawValue)-\(rawValue).json" }
    }

    /// Parse a definition id or a legacy size-first / slot-first alias.
    static func parse(_ raw: String) -> CanvasAddress? {
        parseFull(raw)?.address
    }

    /// Parse plus optional size hint from a legacy alias (`sm-one` → `.sm`).
    static func parseFull(_ raw: String) -> (address: CanvasAddress, aliasSize: CanvasSize?)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if s.isEmpty { return nil }
        if let direct = CanvasAddress(rawValue: s) {
            return (direct, nil)
        }
        switch s {
        case "1": return (.one, nil)
        case "2": return (.two, nil)
        case "3": return (.three, nil)
        default: break
        }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let left = String(parts[0])
        let right = String(parts[1])
        if let size = CanvasSize.parse(left), let address = CanvasAddress(rawValue: right) {
            return (address, size)
        }
        if let address = CanvasAddress(rawValue: left), let size = CanvasSize.parse(right) {
            return (address, size)
        }
        return nil
    }

    static func from(widgetKind: String) -> CanvasAddress? {
        let prefix = "AgentCanvas."
        guard widgetKind.hasPrefix(prefix) else { return nil }
        return parse(String(widgetKind.dropFirst(prefix.count)))
    }
}

enum CanvasSize: String, CaseIterable {
    case sm, md, lg, xl

    /// Documented default budget when a definition is unplaced.
    static let defaultBudget: CanvasSize = .md

    var widgetFamily: WidgetFamily {
        switch self {
        case .sm: return .systemSmall
        case .md: return .systemMedium
        case .lg: return .systemLarge
        case .xl: return .systemExtraLarge
        }
    }

    init?(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall: self = .sm
        case .systemMedium: self = .md
        case .systemLarge: self = .lg
        case .systemExtraLarge: self = .xl
        default: return nil
        }
    }

    static func parse(_ raw: String) -> CanvasSize? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "sm", "s", "small", "systemsmall": return .sm
        case "md", "m", "med", "medium", "systemmedium": return .md
        case "lg", "l", "large", "systemlarge": return .lg
        case "xl", "extralarge", "extra", "extra_large", "extra-large", "systemextralarge":
            return .xl
        default: return nil
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
