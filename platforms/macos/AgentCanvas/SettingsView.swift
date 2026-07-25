import SwiftUI
import AppKit
import WidgetKit

// MARK: - Navigation

private enum SettingsDestination: Hashable {
    case general
    case canvas(CanvasAddress)
}

/// macOS Settings–style host: sidebar of slots, detail with preview + actions.
struct SettingsView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @State private var selection: SettingsDestination? = .general
    @State private var showOnboarding = false
    @State private var showHowTo = false
    @State private var showChecklist = !UserGuide.checklistDismissed
    @State private var statusNote = ""
    @State private var refreshTick = 0

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            reloadWatcher.start()
            if !UserGuide.hasCompletedOnboarding {
                showOnboarding = true
            }
            showChecklist = !UserGuide.checklistDismissed
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshTick &+= 1
            reloadWatcher.refreshCanvasCounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasShowHowTo)) { _ in
            showHowTo = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenConnect)) { note in
            if let client = note.object as? ConnectWizardClient {
                reloadWatcher.preferredConnectClient = client
            }
            openWindow(id: "connect-wizard")
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenSeed)) { _ in
            openWindow(id: "seed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenCloud)) { _ in
            selection = .general
        }
        .sheet(isPresented: $showOnboarding) {
            HowToUseView {
                showOnboarding = false
                showChecklist = !UserGuide.checklistDismissed
            }
        }
        .sheet(isPresented: $showHowTo) {
            HowToUseView(showsDismissActions: true) {
                showHowTo = false
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsDestination.general)
            }

            ForEach(CanvasSize.allCases, id: \.rawValue) { size in
                Section(size.galleryLabel) {
                    ForEach(CanvasAddress.allCases.filter { $0.size == size }) { address in
                        sidebarRow(address)
                            .tag(SettingsDestination.canvas(address))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 280)
        // Force sidebar refresh when content changes
        .id(refreshTick)
    }

    private func sidebarRow(_ address: CanvasAddress) -> some View {
        let doc = CanvasStorage.load(address: address)
        let filled = !doc.isEmptyContent
        let shared = CloudShareIndex.record(forCanvas: address.rawValue) != nil
        let subscribed = CloudSubscriptionStore.subscription(for: address.rawValue) != nil

        return HStack(spacing: 10) {
            Circle()
                .fill(filled ? Color.green.opacity(0.9) : Color.secondary.opacity(0.28))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(address.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(address.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if shared {
                    Image(systemName: "link.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue.opacity(0.85))
                        .help("Published")
                }
                if subscribed {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                        .help("Subscribed to URL")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(address.displayName), \(filled ? "has content" : "empty")")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsDetail(
                showChecklist: $showChecklist,
                showHowTo: $showHowTo,
                statusNote: $statusNote
            )
            .environmentObject(reloadWatcher)
        case .canvas(let address):
            CanvasSettingsDetail(
                address: address,
                statusNote: $statusNote,
                refreshTick: refreshTick
            )
            .environmentObject(reloadWatcher)
            .id(address.rawValue + "-\(refreshTick)")
        }
    }
}

// MARK: - General

private struct GeneralSettingsDetail: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @Binding var showChecklist: Bool
    @Binding var showHowTo: Bool
    @Binding var statusNote: String

    @State private var cloudToggle = CloudFeature.userToggleEnabled
    @State private var apiConfig = CloudConfigStore.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if showChecklist && !UserGuide.checklistDismissed {
                    ChecklistBanner(
                        onOpenConnect: { openWindow(id: "connect-wizard") },
                        onOpenHowTo: { showHowTo = true },
                        onDismiss: {
                            UserGuide.checklistDismissed = true
                            showChecklist = false
                        }
                    )
                }

                statusCards

                settingsForm

                if !statusNote.isEmpty {
                    Text(statusNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("General")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent Canvas")
                .font(.largeTitle.weight(.bold))
            Text("Manage desktop canvases your agent can update. Pick a slot in the sidebar for a live preview and actions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCards: some View {
        HStack(spacing: 12) {
            statusCard(
                title: "Host",
                value: reloadWatcher.isWatching ? "Watching" : "Starting…",
                symbol: reloadWatcher.isWatching ? "antenna.radiowaves.left.and.right" : "ellipsis",
                tint: reloadWatcher.isWatching ? .green : .secondary
            )
            statusCard(
                title: "Filled",
                value: reloadWatcher.canvasFillSummary,
                symbol: "square.grid.3x3.fill",
                tint: .accentColor
            )
            statusCard(
                title: "Version",
                value: Bundle.main.shortVersion,
                symbol: "app.badge",
                tint: .secondary
            )
        }
    }

    private func statusCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            formSection("Get started") {
                formRow("Connect agent", subtitle: "Cursor, Claude Desktop, or manual MCP") {
                    Button("Open…") { openWindow(id: "connect-wizard") }
                }
                formRow("How to use", subtitle: "Short checklist for placing widgets") {
                    Button("Show") { showHowTo = true }
                }
                formRow("Reload widgets", subtitle: "Refresh all WidgetKit timelines") {
                    Button("Reload") {
                        CanvasStorage.mirrorAllAndReload()
                        reloadWatcher.noteManualReload()
                        statusNote = "Widgets reloaded"
                    }
                }
            }

            formSection("Data") {
                formRow("Data folder", subtitle: CanvasStorage.applicationSupportRoot.path) {
                    Button("Reveal") {
                        CanvasStorage.ensureDirectories()
                        NSWorkspace.shared.open(CanvasStorage.applicationSupportRoot)
                    }
                }
                formRow("Clear all canvases", subtitle: "Removes local JSON for every slot") {
                    Button("Clear…", role: .destructive) {
                        try? CanvasStorage.clearAll()
                        statusNote = "All canvases cleared"
                        reloadWatcher.refreshCanvasCounts()
                    }
                }
            }

            #if DEBUG
            formSection("Cloud (debug)") {
                formRow("Cloud features", subtitle: CloudFeature.statusDescription) {
                    Toggle("", isOn: $cloudToggle)
                        .labelsHidden()
                        .onChange(of: cloudToggle) { _, on in
                            CloudFeature.userToggleEnabled = on
                            statusNote = on ? "Cloud features on" : "Cloud features off"
                        }
                }
                if CloudFeature.isEnabled || cloudToggle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API base URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://canvas.velox.test", text: $apiConfig.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save API URL") {
                                do {
                                    try apiConfig.save()
                                    statusNote = "Saved \(apiConfig.normalizedAPIBase)"
                                } catch {
                                    statusNote = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Text("Per-slot publish & subscribe are on each canvas page.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            #endif
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private func formRow<Trailing: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Canvas detail

private struct CanvasSettingsDetail: View {
    let address: CanvasAddress
    @Binding var statusNote: String
    var refreshTick: Int

    @EnvironmentObject private var reloadWatcher: ReloadWatcher

    @State private var publishSlug = ""
    @State private var subURL = ""
    @State private var subPoll = 60
    @State private var subEnabled = true
    @State private var busy = false
    @State private var lastPublicURL = ""
    @State private var cloudConfig = CloudConfigStore.load()

    private var document: CanvasDocument {
        _ = refreshTick
        return CanvasStorage.load(address: address)
    }

    private var share: CloudShareRecord? {
        _ = refreshTick
        return CloudShareIndex.record(forCanvas: address.rawValue)
    }

    private var subscription: CloudSubscription? {
        _ = refreshTick
        return CloudSubscriptionStore.subscription(for: address.rawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                previewBlock
                contentActions
                #if DEBUG
                if CloudFeature.isEnabled {
                    publishBlock
                    subscribeBlock
                }
                #endif
                if !statusNote.isEmpty {
                    Text(statusNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(address.displayName)
        .onAppear {
            cloudConfig = CloudConfigStore.load()
            if let s = share {
                publishSlug = s.slug
                lastPublicURL = s.publicUrl
            }
            if let sub = subscription {
                subURL = sub.url
                subPoll = sub.pollIntervalSeconds
                subEnabled = sub.enabled
            } else {
                subPoll = cloudConfig.defaultPollIntervalSeconds
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(address.displayName)
                    .font(.largeTitle.weight(.bold))
                Text(address.rawValue)
                    .font(.title3.monospaced())
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                badge(
                    document.isEmptyContent ? "Empty" : "Has content",
                    color: document.isEmptyContent ? .secondary : .green
                )
                if share != nil {
                    badge("Published", color: .blue)
                }
                if subscription != nil {
                    badge("Subscribed", color: .orange)
                }
                if let t = document.updatedAt {
                    Text("Updated \(t.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let title = document.title, !title.isEmpty {
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }

    private var previewBlock: some View {
        let tile = ContentClip.defaultTileSize(for: address.size)
        let scale = min(1.0, 320 / max(tile.width, 1))
        let entry = makePreviewEntry(address: address, document: document)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)
            HStack {
                Spacer(minLength: 0)
                CanvasView(entry: entry, isPreview: true)
                    .frame(width: tile.width, height: tile.height)
                    .scaleEffect(scale)
                    .frame(width: tile.width * scale, height: tile.height * scale)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.15, blue: 0.18),
                                Color(red: 0.10, green: 0.11, blue: 0.13),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text("Approximate widget size (\(Int(tile.width))×\(Int(tile.height))). Desktop chrome may differ slightly.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var contentActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)
            HStack(spacing: 10) {
                Button("Copy id") {
                    UserGuide.copyCanvasId(address.rawValue)
                    statusNote = "Copied \(address.rawValue)"
                }
                Button("Copy update prompt") {
                    UserGuide.copyUpdatePrompt(for: address.rawValue)
                    statusNote = "Prompt copied"
                }
                Button("Reload widget") {
                    CanvasStorage.reload(address: address)
                    statusNote = "Reloaded \(address.rawValue)"
                }
                Spacer()
                Button("Clear", role: .destructive) {
                    try? CanvasStorage.clear(address: address)
                    statusNote = "Cleared \(address.rawValue)"
                    reloadWatcher.refreshCanvasCounts()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    #if DEBUG
    private var publishBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish")
                .font(.headline)
            Text("Share this slot’s JSON to canvas cloud. Requires API reachability.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("slug (optional)", text: $publishSlug)
                    .textFieldStyle(.roundedBorder)
                Button("Publish") {
                    Task { await publish() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || document.isEmptyContent)
                Button("Push update") {
                    Task { await pushUpdate() }
                }
                .disabled(busy || share == nil)
                Button("Unshare", role: .destructive) {
                    Task { await unshare() }
                }
                .disabled(busy || share == nil)
            }
            if let share {
                HStack {
                    Image(systemName: "link")
                    Text(share.publicUrl)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(share.publicUrl, forType: .string)
                        statusNote = "URL copied"
                    }
                }
            } else if !lastPublicURL.isEmpty {
                Text(lastPublicURL)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let share {
                Text(
                    CloudKeychain.getToken(slug: share.slug) != nil
                        ? "Edit token stored in Keychain"
                        : "No edit token in Keychain — publish again or paste via MCP"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var subscribeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscribe")
                .font(.headline)
            Text("Pull JSON from a URL into this slot (usually …/api/v1/canvases/{slug}).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Feed URL", text: $subURL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Toggle("Enabled", isOn: $subEnabled)
                Text("Poll every")
                TextField("60", value: $subPoll, format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                Text("seconds")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { saveSubscription() }
                    .buttonStyle(.borderedProminent)
                Button("Fetch now") {
                    Task { await fetchNow() }
                }
                .disabled(busy)
                if subscription != nil {
                    Button("Remove", role: .destructive) {
                        try? CloudSubscriptionStore.remove(canvas: address.rawValue)
                        subURL = ""
                        statusNote = "Subscription removed"
                    }
                }
            }
            if let sub = subscription {
                if let err = sub.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let at = sub.lastFetchAt {
                    Text("Last fetch \(at.formatted())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    @MainActor
    private func publish() async {
        busy = true
        defer { busy = false }
        do {
            try cloudConfig.save()
            let result = try await CloudAPIClient.publish(
                address: address,
                slug: publishSlug.isEmpty ? nil : publishSlug,
                config: cloudConfig
            )
            publishSlug = result.slug
            lastPublicURL = result.publicURL
            statusNote = "Published \(result.slug)"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func pushUpdate() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await CloudAPIClient.updateShared(address: address, config: cloudConfig)
            lastPublicURL = result.publicURL
            statusNote = "Updated \(result.slug)"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func unshare() async {
        busy = true
        defer { busy = false }
        do {
            try await CloudAPIClient.unshare(
                slugOrCanvas: share?.slug ?? address.rawValue,
                config: cloudConfig
            )
            lastPublicURL = ""
            publishSlug = ""
            statusNote = "Unshared"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    private func saveSubscription() {
        let url = subURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else {
            statusNote = "Enter a valid URL"
            return
        }
        let sub = CloudSubscription(
            canvas: address.rawValue,
            url: url,
            pollIntervalSeconds: max(15, subPoll),
            enabled: subEnabled,
            etag: subscription?.etag,
            lastFetchAt: subscription?.lastFetchAt,
            lastError: nil,
            lastStatusCode: nil
        )
        do {
            try CloudSubscriptionStore.upsert(sub)
            try cloudConfig.save()
            statusNote = "Subscription saved"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func fetchNow() async {
        busy = true
        defer { busy = false }
        let sub = subscription ?? CloudSubscription(
            canvas: address.rawValue,
            url: subURL,
            pollIntervalSeconds: max(15, subPoll),
            enabled: true
        )
        do {
            if subscription == nil {
                try CloudSubscriptionStore.upsert(sub)
            }
            try await CloudAPIClient.fetchSubscription(sub)
            statusNote = "Fetched into \(address.rawValue)"
            reloadWatcher.noteManualReload()
        } catch {
            statusNote = error.localizedDescription
        }
    }
    #endif
}

// MARK: - Preview entry

private func makePreviewEntry(address: CanvasAddress, document: CanvasDocument) -> CanvasEntry {
    let tile = ContentClip.defaultTileSize(for: address.size)
    let hasTitle = (document.title?.isEmpty == false) && address.size != .sm
    let hasTimestamp = document.updatedAt != nil
    let live = !document.isEmptyContent
    var budget = ContentClip.contentBudget(
        displaySize: tile,
        size: address.size,
        hasTitle: hasTitle && live,
        hasTimestamp: hasTimestamp && live,
        reserveOverflowLine: false
    )
    var clip = ContentClip.apply(document: document, size: address.size, maxHeight: budget)
    if clip.truncated {
        budget = ContentClip.contentBudget(
            displaySize: tile,
            size: address.size,
            hasTitle: hasTitle && live,
            hasTimestamp: hasTimestamp && live,
            reserveOverflowLine: true
        )
        clip = ContentClip.apply(document: document, size: address.size, maxHeight: budget)
    }
    return CanvasEntry(
        date: Date(),
        address: address,
        document: document,
        isPlaceholder: document.isEmptyContent,
        clip: clip,
        displaySize: tile
    )
}

