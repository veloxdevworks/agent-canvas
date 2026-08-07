import SwiftUI

/// Semantic tone — maps to system colors (Adaptive Cards: attention/good/warning/…).
enum CanvasTone: String, Codable, Equatable {
    case critical, warning, success, info, muted
}

/// Semantic emphasis — maps to system font weights (Adaptive Cards: bolder/lighter).
enum CanvasEmphasis: String, Codable, Equatable {
    case strong, normal, subtle
}

enum StyleTokens {
    static func color(for tone: CanvasTone?) -> Color? {
        guard let tone else { return nil }
        switch tone {
        case .critical: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return .blue
        case .muted: return .secondary
        }
    }

    static func foreground(tone: CanvasTone?, default defaultColor: Color = .primary) -> Color {
        color(for: tone) ?? defaultColor
    }

    static func fontWeight(for emphasis: CanvasEmphasis?) -> Font.Weight {
        switch emphasis {
        case .strong: return .semibold
        case .subtle: return .light
        case .normal, .none: return .regular
        }
    }
}
