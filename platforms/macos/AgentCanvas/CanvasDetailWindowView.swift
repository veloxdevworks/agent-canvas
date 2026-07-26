import SwiftUI

struct CanvasDetailWindowView: View {
    let address: CanvasAddress
    @State private var document: CanvasDocument = CanvasDocument.empty
    
    @EnvironmentObject var reloadWatcher: ReloadWatcher
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text(document.title ?? address.displayName)
                        .font(.largeTitle.weight(.bold))
                        .textSelection(.enabled)
                    
                    Spacer()
                    
                    Text(address.rawValue)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Actual Canvas
                let totalListItems = document.sections.reduce(0) { sum, section in
                    if case .list(let l) = section { return sum + l.items.count }
                    return sum
                }
                let entry = CanvasEntry(
                    date: Date(),
                    address: address,
                    document: document,
                    isPlaceholder: false,
                    clip: ContentClip.Result(
                        shown: document.sections,
                        droppedTypes: [],
                        truncated: false,
                        listItemsShown: totalListItems,
                        listItemsTotal: totalListItems
                    ),
                    displaySize: CGSize(width: 400, height: 800)
                )
                
                CanvasView(entry: entry, isPreview: false, disableClipping: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(document.title ?? address.displayName)
        .onAppear {
            loadDocument()
        }
        .onChange(of: reloadWatcher.lastReload) { _ in
            loadDocument()
        }
    }
    
    private func loadDocument() {
        document = CanvasStorage.load(address: address)
    }
}
