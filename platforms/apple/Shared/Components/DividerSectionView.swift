import SwiftUI

struct DividerSectionView: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
    }
}
