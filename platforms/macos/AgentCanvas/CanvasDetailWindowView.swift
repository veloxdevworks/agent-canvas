import SwiftUI
import AppKit

struct CanvasDetailWindowView: View {
    let address: CanvasAddress
    @State private var document: CanvasDocument = CanvasDocument.empty
    /// Measured height of the padded content stack (not the window chrome).
    @State private var measuredContentHeight: CGFloat = 0
    @State private var hostWindow: NSWindow?

    @EnvironmentObject var reloadWatcher: ReloadWatcher

    private static let minWidth: CGFloat = 360
    private static let idealWidth: CGFloat = 480
    private static let minHeight: CGFloat = 200

    private static var maxHeight: CGFloat {
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        return min(720, screenH * 0.85)
    }

    private var clampedHeight: CGFloat {
        let raw = measuredContentHeight > 1 ? measuredContentHeight : Self.minHeight
        return min(max(raw, Self.minHeight), Self.maxHeight)
    }

    private var needsScroll: Bool {
        measuredContentHeight > Self.maxHeight + 0.5
    }

    var body: some View {
        Group {
            if needsScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    measuredBody
                }
            } else {
                measuredBody
            }
        }
        .frame(width: Self.idealWidth, height: clampedHeight, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(HostWindowReader { hostWindow = $0 })
        .navigationTitle(document.title ?? address.displayName)
        .onPreferenceChange(DetailContentHeightKey.self) { height in
            guard height > 1, abs(height - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = height
        }
        .onAppear {
            loadDocument()
        }
        .onChange(of: reloadWatcher.lastReload) { _ in
            loadDocument()
        }
        .onChange(of: clampedHeight) { newHeight in
            applyWindowContentSize(height: newHeight)
        }
        .onChange(of: hostWindow) { _ in
            applyWindowContentSize(height: clampedHeight)
        }
    }

    private var measuredBody: some View {
        contentStack
            .padding(24)
            .frame(width: Self.idealWidth, alignment: .topLeading)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DetailContentHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
    }

    @ViewBuilder
    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(document.title ?? address.displayName)
                    .font(.largeTitle.weight(.bold))
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Text(address.rawValue)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            let sections = document.detailSections
            let totalListItems = sections.reduce(0) { sum, section in
                if case .list(_, let items, _) = section { return sum + items.count }
                return sum
            }
            let entry = CanvasEntry(
                date: Date(),
                address: address,
                document: CanvasDocument(
                    version: document.version,
                    updatedAt: document.updatedAt,
                    title: document.title,
                    onOpen: document.onOpen,
                    sections: sections,
                    detail: nil
                ),
                isPlaceholder: false,
                clip: ContentClip.Result(
                    shown: sections,
                    shownIndices: Array(sections.indices),
                    droppedTypes: [],
                    truncated: false,
                    listItemsShown: totalListItems,
                    listItemsTotal: totalListItems
                ),
                displaySize: CGSize(width: Self.idealWidth, height: Self.maxHeight)
            )

            CanvasView(
                entry: entry,
                isPreview: false,
                disableClipping: true,
                actionInteraction: .hostButton,
                onListItemAction: { _, _, item in
                    guard let action = item.action else { return }
                    let outcome = CanvasActionDispatcher.perform(
                        action,
                        canvasId: address.rawValue,
                        context: "detail.list"
                    )
                    if case .expand = outcome {
                        loadDocument()
                    }
                }
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func loadDocument() {
        document = CanvasStorage.load(address: address)
    }

    /// AppKit is authoritative: SwiftUI `.contentSize` often keeps a restored tall frame.
    private func applyWindowContentSize(height: CGFloat) {
        let width = Self.idealWidth
        DispatchQueue.main.async {
            guard let window = hostWindow else { return }
            let current = window.contentLayoutRect.size
            if abs(current.height - height) < 2, abs(current.width - width) < 2 {
                return
            }
            window.setContentSize(NSSize(width: width, height: height))
        }
    }
}

/// Reads the AppKit window hosting this SwiftUI hierarchy.
private struct HostWindowReader: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}

private enum DetailContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
