import Foundation

/// Summary row model shared by Settings / Seed demos.
struct AddressSummary: Identifiable {
    let id: String
    let name: String
    let size: CanvasSize
    let hasContent: Bool
    let detail: String
}
