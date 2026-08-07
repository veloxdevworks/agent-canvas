import SwiftUI

struct KeyValueSectionView: View {
    let items: [KeyValueItem]
    let size: CanvasSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.key)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.value)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(StyleTokens.foreground(tone: item.tone))
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
