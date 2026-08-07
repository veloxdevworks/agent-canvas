import SwiftUI

struct IconSectionView: View {
    let name: IconName
    let tone: CanvasTone?
    let size: IconSize?
    let layoutSize: CanvasSize

    var body: some View {
        let token = size ?? .md
        let height = ContentClip.iconHeight(for: layoutSize, size: token)
        CanvasIcon.view(
            name: name,
            tone: tone,
            pointSize: CanvasIcon.pointSize(for: token, layout: layoutSize)
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
    }
}
