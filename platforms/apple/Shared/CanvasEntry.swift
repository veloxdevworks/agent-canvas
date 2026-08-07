import Foundation
import CoreGraphics
import WidgetKit

struct CanvasEntry: TimelineEntry {
    let date: Date
    let address: CanvasAddress
    let document: CanvasDocument
    let isPlaceholder: Bool
    let clip: ContentClip.Result
    /// WidgetKit’s offered size for this family — used to pack so ideal height fits.
    let displaySize: CGSize
}
