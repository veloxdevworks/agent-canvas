import SwiftUI

struct SlotsListView: View {
    @EnvironmentObject private var oauth: VeloxOAuthSession
    @EnvironmentObject private var sync: SubscriptionSync
    @EnvironmentObject private var router: DeepLinkRouter

    @State private var showSubscribe = false
    @State private var showSettings = false
    @State private var tick = 0

    var body: some View {
        List {
            Section {
                ForEach(CanvasAddress.allCases) { address in
                    Button {
                        router.openDetail(address)
                    } label: {
                        SlotRow(address: address)
                    }
                }
            } header: {
                Text("Slots")
            } footer: {
                Text(sync.statusLine)
            }
        }
        .navigationTitle("Agent Canvas")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await sync.syncAll(reason: .manual) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(sync.isSyncing)

                Button {
                    showSubscribe = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await sync.syncAll(reason: .manual)
            tick += 1
        }
        .sheet(isPresented: $showSubscribe) {
            SubscribeSheet(initialSlug: "")
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        // Force row refresh after sync / subscribe.
        .id(tick)
        .onChange(of: sync.lastSyncAt) { _ in
            tick += 1
        }
        .onChange(of: router.subscribeSlug) { slug in
            if slug != nil {
                showSubscribe = false
            }
        }
    }
}

struct SlotRow: View {
    let address: CanvasAddress

    private var document: CanvasDocument {
        CanvasStorage.load(address: address)
    }

    private var subscription: CloudSubscription? {
        CloudSubscriptionStore.subscription(for: address.rawValue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(address.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(address.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let title = document.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else if document.isEmptyContent {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                if let sub = subscription {
                    Text(slugLabel(for: sub))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func slugLabel(for sub: CloudSubscription) -> String {
        if let url = URL(string: sub.url) {
            return url.lastPathComponent
        }
        return sub.url
    }
}
