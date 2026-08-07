import SwiftUI

/// Curated portable icon names — keep in sync with Rust `IconName` / JSON Schema `iconName`.
enum IconName: String, Codable, Equatable, CaseIterable {
    case check, close, warning, alert, info, help, sparkle
    case search, link, copy, refresh, play, pause, stop
    case rocket, bug, clock, calendar, person, people
    case folder, file, image, chart, settings, lock, key
    case cloud, server, database

    /// SF Symbol for this portable name (host mapping only — never in JSON).
    var systemImage: String {
        switch self {
        case .check: return "checkmark.circle.fill"
        case .close: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .alert: return "exclamationmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .help: return "questionmark.circle.fill"
        case .sparkle: return "sparkles"
        case .search: return "magnifyingglass"
        case .link: return "link"
        case .copy: return "doc.on.doc"
        case .refresh: return "arrow.clockwise"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        case .rocket: return "rocket.fill"
        case .bug: return "ladybug.fill"
        case .clock: return "clock.fill"
        case .calendar: return "calendar"
        case .person: return "person.fill"
        case .people: return "person.2.fill"
        case .folder: return "folder.fill"
        case .file: return "doc.fill"
        case .image: return "photo"
        case .chart: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        case .lock: return "lock.fill"
        case .key: return "key.fill"
        case .cloud: return "cloud.fill"
        case .server: return "server.rack"
        case .database: return "externaldrive.fill"
        }
    }
}

enum IconSize: String, Codable, Equatable {
    case sm, md, lg

    static let `default`: IconSize = .md
}

enum CanvasIcon {
    static func view(name: IconName, tone: CanvasTone?, pointSize: CGFloat) -> some View {
        Image(systemName: name.systemImage)
            .font(.system(size: pointSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(StyleTokens.foreground(tone: tone, default: .secondary))
            .accessibilityLabel(name.rawValue)
    }

    static func leading(name: IconName?, tone: CanvasTone?, pointSize: CGFloat = 12) -> some View {
        Group {
            if let name {
                view(name: name, tone: tone, pointSize: pointSize)
            }
        }
    }

    static func pointSize(for size: IconSize?, layout: CanvasSize) -> CGFloat {
        let token = size ?? .default
        let spec = LayoutSpec.size(layout)
        switch token {
        case .sm: return spec.iconHeightSm * 0.75
        case .md: return spec.iconHeightMd * 0.75
        case .lg: return spec.iconHeightLg * 0.75
        }
    }
}
