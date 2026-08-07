import SwiftUI

struct BadgesSectionView: View {
    let items: [BadgeItem]
    let size: CanvasSize

    var body: some View {
        // Flow-ish wrap via LazyVGrid for glance density.
        let cols = size == .sm ? 2 : (size == .md ? 3 : 4)
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols),
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                Text(item.text)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            (StyleTokens.color(for: item.tone) ?? Color.secondary).opacity(0.2)
                        )
                    )
                    .foregroundStyle(StyleTokens.foreground(tone: item.tone, default: .secondary))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
