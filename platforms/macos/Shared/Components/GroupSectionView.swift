import SwiftUI

/// Detail-oriented flex container. Children are pre-erased to break recursive `some View`.
struct GroupSectionView: View {
    let direction: GroupDirection
    let gap: SpacerSize?
    let align: GroupAlign?
    let childViews: [AnyView]

    var body: some View {
        let spacing = gap?.gapPoints ?? 8
        switch direction {
        case .row:
            HStack(alignment: stackAlignment, spacing: spacing) {
                ForEach(Array(childViews.enumerated()), id: \.offset) { _, child in
                    child
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .column:
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(childViews.enumerated()), id: \.offset) { _, child in
                    child
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stackAlignment: VerticalAlignment {
        switch align {
        case .center: return .center
        case .end: return .bottom
        case .start, .stretch, .none: return .top
        }
    }
}
