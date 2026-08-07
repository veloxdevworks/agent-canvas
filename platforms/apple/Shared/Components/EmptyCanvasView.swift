import SwiftUI

/// Size-aware empty chrome for glance tiles and detail/preview when a canvas has no content.
struct EmptyCanvasView: View {
    let address: CanvasAddress
    var fillTile: Bool = true
    var edgeInset: CGFloat

    private var size: CanvasSize { address.size }

    private var detail: String {
        "Click here to learn how to use."
    }

    private var iconPointSize: CGFloat {
        switch size {
        case .sm: return 28
        case .md: return 32
        case .lg, .xl: return 36
        }
    }

    private var accessibilityText: String {
        "No content. \(detail)"
    }

    var body: some View {
        VStack(spacing: size == .sm ? 8 : 10) {
            CanvasIcon.view(name: .sparkle, tone: .muted, pointSize: iconPointSize)

            VStack(spacing: 4) {
                Text("No content")
                    .font(size == .sm ? .subheadline.weight(.semibold) : .headline)
                    .tracking(0.2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(size == .sm ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(edgeInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillTile ? .infinity : nil,
            alignment: .center
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the how to use guide")
    }
}
