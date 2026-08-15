import Foundation
import CoreGraphics
import WidgetKit

struct CanvasEntry: TimelineEntry {
    let date: Date
    let address: CanvasAddress
    /// Family this entry was packed for (`context.family` on the widget).
    let size: CanvasSize
    let document: CanvasDocument
    let isPlaceholder: Bool
    let clip: ContentClip.Result
    /// WidgetKit’s offered size for this family — used to pack so ideal height fits.
    let displaySize: CGSize
    /// Present only for cloud-subscribed slots (slug / last sync / stale). Local tiles stay nil.
    let provenance: SubscriptionProvenance? = nil
}
