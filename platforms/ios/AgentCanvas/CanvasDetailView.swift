import SwiftUI

struct CanvasDetailView: View {
    let address: CanvasAddress

    @EnvironmentObject private var sync: SubscriptionSync
    @State private var document: CanvasDocument = .empty
    @State private var showUnsubscribeConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(document.title ?? address.displayName)
                        .font(.title.weight(.bold))
                    Spacer(minLength: 8)
                    Text(address.rawValue)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if let sub = CloudSubscriptionStore.subscription(for: address.rawValue) {
                    Label(sub.url, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let entry = CanvasEntry(
                    date: Date(),
                    address: address,
                    document: document,
                    isPlaceholder: false,
                    clip: ContentClip.apply(document: document, size: address.size),
                    displaySize: CGSize(width: 0, height: ContentClip.defaultTileHeight(for: address.size))
                )

                CanvasView(
                    entry: entry,
                    isPreview: true,
                    disableClipping: true,
                    actionInteraction: .hostButton,
                    onListItemAction: { section, item, listItem in
                        if let action = listItem.action {
                            _ = IOSActionDispatcher.perform(action, canvasId: address.rawValue)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(20)
        }
        .navigationTitle(address.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh") {
                        Task { await refresh() }
                    }
                    if CloudSubscriptionStore.subscription(for: address.rawValue) != nil {
                        Button("Unsubscribe", role: .destructive) {
                            showUnsubscribeConfirm = true
                        }
                    } else {
                        // Allow clearing local content even without a subscription.
                        Button("Clear slot", role: .destructive) {
                            try? CanvasStorage.clear(address: address)
                            load()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Unsubscribe \(address.rawValue)?",
            isPresented: $showUnsubscribeConfirm,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe, keep content") {
                try? sync.unsubscribe(address: address, clearContent: false)
                load()
            }
            Button("Unsubscribe and clear", role: .destructive) {
                try? sync.unsubscribe(address: address, clearContent: true)
                load()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { load() }
        .onChange(of: sync.lastSyncAt) { _ in load() }
    }

    private func load() {
        document = CanvasStorage.load(address: address)
    }

    private func refresh() async {
        if let sub = CloudSubscriptionStore.subscription(for: address.rawValue) {
            do {
                try await CloudAPIClient.fetchSubscription(sub)
            } catch {
                NSLog("AgentCanvas iOS refresh: \(error.localizedDescription)")
            }
        }
        load()
    }
}
