import SwiftUI
import AppKit
import WidgetKit

// MARK: - Navigation

private enum SettingsDestination: Hashable {
    case general
    #if DEBUG
    case dev
    #endif
    case canvas(CanvasAddress)
}

/// macOS Settings–style host: sidebar of slots, detail with preview + actions.
struct SettingsView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @State private var selection: SettingsDestination? = .general
    @State private var showOnboarding = false
    @State private var showHowTo = false
    #if DEBUG
    @State private var pendingSubscribe: SubscribeSlugRequest?
    #endif
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
        .frame(minWidth: 860, minHeight: 520)
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
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenSeed)) { _ in
            openWindow(id: "seed")
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenCloud)) { _ in
            #if DEBUG
            selection = .dev
            #else
            selection = .general
            #endif
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasShowSubscribe)) { note in
            selection = .general
            if let slug = note.object as? String, !slug.isEmpty {
                pendingSubscribe = SubscribeSlugRequest(slug: slug)
            }
        }
        #endif
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
        #if DEBUG
        .sheet(item: $pendingSubscribe) { request in
            SubscribeDeepLinkSheet(slug: request.slug) { address in
                selection = .canvas(address)
                pendingSubscribe = nil
                refreshTick &+= 1
                statusNote = "Subscribed \(request.slug) → \(address.rawValue)"
            } onCancel: {
                pendingSubscribe = nil
            }
        }
        #endif
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsDestination.general)
                #if DEBUG
                Label("Dev", systemImage: "hammer")
                    .tag(SettingsDestination.dev)
                #endif
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
    }

    private func sidebarRow(_ address: CanvasAddress) -> some View {
        // Depend on poll tick so filled/title/share badges update without remounting the List.
        let _ = refreshTick
        let doc = CanvasStorage.load(address: address)
        let filled = !doc.isEmptyContent
        let shared = CloudShareIndex.record(forCanvas: address.rawValue) != nil
        let subscribed = CloudSubscriptionStore.subscription(for: address.rawValue) != nil
        let label: String = {
            if let title = doc.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return address.displayName
        }()

        return HStack(spacing: 10) {
            Circle()
                .fill(filled ? Color.green.opacity(0.9) : Color.secondary.opacity(0.28))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
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
        .accessibilityLabel("\(label), \(address.rawValue), \(filled ? "has content" : "empty")")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsDetail(
                showChecklist: $showChecklist,
                showHowTo: $showHowTo
            )
            .environmentObject(reloadWatcher)
        #if DEBUG
        case .dev:
            DevSettingsDetail(
                statusNote: $statusNote,
                refreshTick: refreshTick
            )
            .environmentObject(reloadWatcher)
        #endif
        case .canvas(let address):
            CanvasSettingsDetail(
                address: address,
                statusNote: $statusNote,
                refreshTick: refreshTick
            )
            .environmentObject(reloadWatcher)
            // Identity by slot only — including refreshTick remounted the view every 2s
            // and wiped @State (publish fields) + ScrollView position.
            .id(address.rawValue)
        }
    }
}

// MARK: - General

private struct GeneralSettingsDetail: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @Binding var showChecklist: Bool
    @Binding var showHowTo: Bool

    @State private var confirmClearAll = false
    @State private var notificationsEnabled = NotificationPrefs.notificationsEnabled
    @State private var notificationNote = ""
    @State private var showNotificationSettingsButton = false
    @State private var notificationEnableInFlight = false

    var body: some View {
        Form {
            if showChecklist && !UserGuide.checklistDismissed {
                Section {
                    ChecklistBanner(
                        onOpenConnect: { openWindow(id: "connect-wizard") },
                        onOpenHowTo: { showHowTo = true },
                        onDismiss: {
                            UserGuide.checklistDismissed = true
                            showChecklist = false
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            Section {
                LabeledContent("Connect Agent") {
                    Button("Open…") {
                        openWindow(id: "connect-wizard")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(
                                name: .agentCanvasConnectShowLanding,
                                object: nil
                            )
                        }
                    }
                }
                LabeledContent("How to Use") {
                    Button("Show") { showHowTo = true }
                }
            } header: {
                Text("Agent")
            } footer: {
                Text("Connect an MCP client so agents can update the canvases listed in the sidebar.")
            }

            Section {
                Toggle(
                    "Notify when canvases change",
                    isOn: Binding(
                        get: { notificationsEnabled },
                        set: { newValue in
                            if newValue {
                                guard !notificationEnableInFlight else { return }
                                notificationEnableInFlight = true
                                // Keep the toggle on while the system dialog is up so SwiftUI
                                // doesn't snap back and call set(false) mid-request.
                                notificationsEnabled = true
                                notificationNote = ""
                                showNotificationSettingsButton = false
                                Task {
                                    let result = await CanvasChangeNotifier.shared.enableFromUser()
                                    notificationsEnabled = result.enabled
                                    notificationNote = result.note
                                    showNotificationSettingsButton = result.showOpenSettings
                                    notificationEnableInFlight = false
                                }
                            } else if notificationEnableInFlight {
                                // Ignore binding churn while permission is in flight.
                                return
                            } else {
                                CanvasChangeNotifier.shared.disableFromUser()
                                notificationsEnabled = false
                                notificationNote = ""
                                showNotificationSettingsButton = false
                            }
                        }
                    )
                )
                .disabled(notificationEnableInFlight)
                if !notificationNote.isEmpty {
                    Text(notificationNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showNotificationSettingsButton {
                    Button("Open System Settings…") {
                        CanvasChangeNotifier.openSystemNotificationSettings()
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Shows a system notification when an agent changes canvas content. The Agent Canvas host must be running."
                )
            }
            .task {
                let result = await CanvasChangeNotifier.shared.reconcilePreferenceWithSystem()
                notificationsEnabled = result.enabled
                if !result.note.isEmpty {
                    notificationNote = result.note
                    showNotificationSettingsButton = result.showOpenSettings
                }
            }

            Section {
                LabeledContent("Timelines") {
                    Button("Reload") {
                        CanvasStorage.mirrorAllAndReload()
                        reloadWatcher.noteManualReload()
                    }
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text("Force WidgetKit to refresh every Agent Canvas widget on the desktop.")
            }

            Section {
                LabeledContent("Updates") {
                    Button("Check for Updates…") {
                        AppUpdater.shared.checkForUpdates()
                    }
                }
                LabeledContent("Privacy") {
                    Button("View…") {
                        UserGuide.openPrivacy()
                    }
                }
            } header: {
                Text("App")
            } footer: {
                Text("Agent Canvas also checks for updates automatically in the background.")
            }

            Section {
                LabeledContent("Folder") {
                    Button("Reveal in Finder") {
                        CanvasStorage.ensureDirectories()
                        NSWorkspace.shared.open(CanvasStorage.applicationSupportRoot)
                    }
                }
                Text(CanvasStorage.applicationSupportRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Storage")
            }

            Section {
                Button("Clear All Canvases…", role: .destructive) {
                    confirmClearAll = true
                }
            } footer: {
                Text("Deletes local JSON for every slot. Cloud publishes and subscriptions are kept.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .confirmationDialog(
            "Clear all canvases?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                try? CanvasStorage.clearAll()
                reloadWatcher.syncAllLastSeen()
                reloadWatcher.refreshCanvasCounts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local content from every slot. This can’t be undone.")
        }
    }
}

#if DEBUG
// MARK: - Dev

private struct DevSettingsDetail: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @Binding var statusNote: String
    var refreshTick: Int = 0

    @State private var cloudToggle = CloudFeature.userToggleEnabled
    @State private var apiConfig = CloudConfigStore.load()
    @State private var shares: [CloudShareRecord] = []
    @State private var subscriptions: [CloudSubscription] = []
    @State private var cloudBusy = false
    @ObservedObject private var oauth = VeloxOAuthSession.shared

    var body: some View {
        Form {
            Section {
                Toggle("Cloud Features", isOn: $cloudToggle)
                    .onChange(of: cloudToggle) { _, on in
                        CloudFeature.userToggleEnabled = on
                    }
                TextField("API Base URL", text: $apiConfig.apiBaseURL)
                LabeledContent("Default poll (seconds)") {
                    TextField(
                        "",
                        value: $apiConfig.defaultPollIntervalSeconds,
                        format: .number
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                }
                HStack {
                    Spacer()
                    Button("Reset") {
                        apiConfig.apiBaseURL = CloudConfigStore.defaultAPIBase
                        apiConfig.defaultPollIntervalSeconds = CloudConfigStore.defaultPoll
                    }
                    Button("Save") { saveCloudConfig() }
                        .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Cloud")
            } footer: {
                Text(
                    "\(CloudFeature.statusDescription). Publish and subscribe live on each canvas page. Deep link: agentcanvas://subscribe?slug=…"
                )
            }

            if CloudFeature.isEnabled || cloudToggle {
                Section {
                    cloudAccountSection
                } header: {
                    Text("Account")
                } footer: {
                    Text(
                        "Velox OAuth (PKCE S256, \(AgentCanvasConstants.oauthClientId)). Audience \(apiConfig.resourceOrigin) is sent on token/refresh only."
                    )
                }

                Section {
                    cloudSharesOverview
                } header: {
                    Text("Published from This Mac")
                }

                Section {
                    cloudSubscriptionsOverview
                } header: {
                    Text("Subscriptions")
                }
            }

            Section {
                LabeledContent("Seed Demos") {
                    Button("Open…") { openWindow(id: "seed") }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Debug-only. This tab is omitted from release builds.")
            }

            if !statusNote.isEmpty {
                Section {
                    Text(statusNote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dev")
        .onAppear(perform: reloadCloudLocal)
        .onChange(of: refreshTick) { _, _ in refreshCloudLists() }
        .onChange(of: cloudToggle) { _, _ in reloadCloudLocal() }
    }

    private func reloadCloudLocal() {
        cloudToggle = CloudFeature.userToggleEnabled
        apiConfig = CloudConfigStore.load()
        refreshCloudLists()
        oauth.refreshPublishedState()
    }

    private func refreshCloudLists() {
        shares = CloudShareIndex.load()
        subscriptions = CloudSubscriptionStore.load()
        oauth.refreshPublishedState()
    }

    private func saveCloudConfig() {
        do {
            try apiConfig.save()
            statusNote = "Saved \(apiConfig.normalizedAPIBase)"
            reloadCloudLocal()
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @ViewBuilder
    private var cloudAccountSection: some View {
        if oauth.isSignedIn {
            LabeledContent("Signed In As") {
                Text(oauth.accountLabel ?? "Velox account")
            }
            if let exp = oauth.expiresAt {
                LabeledContent("Access Expires") {
                    Text(exp.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            Button("Sign Out") {
                Task { await oauth.signOut(config: apiConfig) }
            }
            .disabled(oauth.isBusy)
        } else {
            LabeledContent("Account") {
                HStack(spacing: 8) {
                    if oauth.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Sign In…") {
                        Task {
                            do {
                                try await oauth.signIn(
                                    config: apiConfig,
                                    presentingWindow: NSApp.keyWindow
                                )
                            } catch {
                                statusNote = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(oauth.isBusy)
                }
            }
        }
        if let err = oauth.lastError, !err.isEmpty {
            Text(err)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var cloudSharesOverview: some View {
        if shares.isEmpty {
            Text("None yet — open a canvas page and use Publish.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares) { s in
                    HStack(spacing: 8) {
                        Text(s.canvas)
                            .font(.caption.monospaced())
                        Text("→")
                            .foregroundStyle(.tertiary)
                        Text(s.slug)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(CloudKeychain.getToken(slug: s.slug) != nil ? "token ✓" : "no token")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(s.publicUrl, forType: .string)
                            statusNote = "Copied \(s.publicUrl)"
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cloudSubscriptionsOverview: some View {
        if subscriptions.isEmpty {
            Text("None yet — open a canvas page and use Subscribe.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(subscriptions) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: {
                                        CloudSubscriptionStore.subscription(for: s.canvas)?.enabled
                                            ?? s.enabled
                                    },
                                    set: { on in
                                        var copy = s
                                        copy.enabled = on
                                        try? CloudSubscriptionStore.upsert(copy)
                                        reloadCloudLocal()
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Text(s.canvas)
                                .font(.caption.monospaced().weight(.semibold))
                            Text("every \(s.pollIntervalSeconds)s")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 4)
                            Button("Fetch") {
                                Task { await fetchSubscription(s) }
                            }
                            .buttonStyle(.borderless)
                            .disabled(cloudBusy)
                            Button("Remove", role: .destructive) {
                                try? CloudSubscriptionStore.remove(canvas: s.canvas)
                                reloadCloudLocal()
                                statusNote = "Removed subscription for \(s.canvas)"
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(s.url)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let err = s.lastError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        } else if let at = s.lastFetchAt {
                            Text("Last fetch \(at.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func fetchSubscription(_ sub: CloudSubscription) async {
        cloudBusy = true
        defer { cloudBusy = false }
        do {
            try await CloudAPIClient.fetchSubscription(sub)
            statusNote = "Fetched into \(sub.canvas)"
            reloadWatcher.noteManualReload()
            reloadCloudLocal()
        } catch {
            statusNote = error.localizedDescription
            reloadCloudLocal()
        }
    }
}
#endif

// MARK: - Canvas detail

private struct CanvasSettingsDetail: View {
    let address: CanvasAddress
    @Binding var statusNote: String
    var refreshTick: Int

    @EnvironmentObject private var reloadWatcher: ReloadWatcher

    @State private var publishSlug = ""
    @State private var publishError: String?
    @State private var publishVisibility: CloudAPIClient.PublishVisibility = .public
    @State private var organizations: [CloudOrganization] = []
    @State private var selectedOrgId: String?
    @State private var orgsLoading = false
    @State private var orgsError: String?
    @State private var autoPushUpdates = false
    @State private var showPublishSheet = false
    @State private var showSubscribeSheet = false
    @State private var subURL = ""
    @State private var subPoll = 60
    @State private var subEnabled = true
    @State private var subError: String?
    @State private var busy = false
    @State private var lastPublicURL = ""
    @State private var cloudConfig = CloudConfigStore.load()
    @State private var muteNotifications = false
    @ObservedObject private var oauth = VeloxOAuthSession.shared

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

    /// Canvas JSON title when set; otherwise the slot display name (e.g. "Small 1").
    private var resolvedTitle: String {
        if let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return address.displayName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                metaBlock
                notificationsBlock
                previewBlock
                historyBlock
                #if DEBUG
                if CloudFeature.isEnabled {
                    if let share {
                        publishedMainBlock(share)
                    } else if let sub = subscription {
                        subscribedMainBlock(sub)
                    }
                }
                #endif
                if !statusNote.isEmpty {
                    Text(statusNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Inline so the large system title doesn’t leave a gap above our header.
        .navigationTitle(resolvedTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        UserGuide.copyCanvasId(address.rawValue)
                        statusNote = "Copied \(address.rawValue)"
                    } label: {
                        Label("Copy id", systemImage: "doc.on.doc")
                    }
                    Button {
                        UserGuide.copyUpdatePrompt(for: address.rawValue)
                        statusNote = "Prompt copied"
                    } label: {
                        Label("Copy update prompt", systemImage: "text.badge.plus")
                    }
                    Divider()
                    Button {
                        CanvasStorage.reload(address: address)
                        statusNote = "Reloaded \(address.rawValue)"
                    } label: {
                        Label("Reload widget", systemImage: "arrow.clockwise")
                    }
                    #if DEBUG
                    if CloudFeature.isEnabled {
                        Divider()
                        cloudMenuItems
                    }
                    #endif
                    Divider()
                    Button(role: .destructive) {
                        try? CanvasStorage.clear(address: address)
                        reloadWatcher.syncLastSeen(address: address)
                        statusNote = "Cleared \(address.rawValue)"
                        reloadWatcher.refreshCanvasCounts()
                    } label: {
                        Label("Clear canvas", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Canvas actions")
                .accessibilityLabel("Canvas actions")
            }
        }
        #if DEBUG
        .sheet(isPresented: $showPublishSheet) {
            publishSheet
        }
        .sheet(isPresented: $showSubscribeSheet) {
            subscribeSheet
        }
        #endif
        .onAppear {
            cloudConfig = CloudConfigStore.load()
            muteNotifications = NotificationPrefs.isMuted(address)
            if let s = share {
                publishSlug = s.slug
                lastPublicURL = s.publicUrl
                autoPushUpdates = s.resolvedAutoPush
                if let vis = s.visibility, let parsed = CloudAPIClient.PublishVisibility(rawValue: vis) {
                    publishVisibility = parsed
                }
                selectedOrgId = s.orgId
            }
            if let sub = subscription {
                subURL = sub.url
                subPoll = sub.pollIntervalSeconds
                subEnabled = sub.enabled
            } else {
                subPoll = cloudConfig.defaultPollIntervalSeconds
            }
            #if DEBUG
            if oauth.isSignedIn {
                Task { await loadOrganizations() }
            }
            #endif
        }
        #if DEBUG
        .onChange(of: oauth.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await loadOrganizations() }
            } else {
                organizations = []
                selectedOrgId = nil
            }
        }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private var cloudMenuItems: some View {
        if share != nil {
            Button(role: .destructive) {
                Task { await unshare() }
            } label: {
                Label("Unpublish", systemImage: "link.badge.minus")
            }
            .disabled(busy)
        } else if subscription == nil {
            Button {
                publishError = nil
                showPublishSheet = true
                if oauth.isSignedIn {
                    Task { await loadOrganizations() }
                }
            } label: {
                Label("Publish…", systemImage: "arrow.up.circle")
            }
            .disabled(document.isEmptyContent)
        }

        if subscription != nil {
            Button(role: .destructive) {
                unsubscribeKeepingContent()
            } label: {
                Label("Unsubscribe", systemImage: "arrow.down.circle")
            }
        } else if share == nil {
            Button {
                subError = nil
                if subURL.isEmpty {
                    subURL = ""
                }
                showSubscribeSheet = true
            } label: {
                Label("Subscribe…", systemImage: "arrow.down.circle")
            }
        }
    }
    #endif

    /// Id/status badges.
    private var metaBlock: some View {
        HStack(spacing: 8) {
            idBadge(address.rawValue)
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
        }
    }

    private var notificationsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Mute notifications for this canvas",
                isOn: Binding(
                    get: { muteNotifications },
                    set: { newValue in
                        muteNotifications = newValue
                        NotificationPrefs.setMuted(address, newValue)
                    }
                )
            )
            .toggleStyle(.switch)
            Text("When notifications are enabled in General, skip banners for this slot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func idBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .help("Canvas id")
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
                                Color(red: 0.32, green: 0.18, blue: 0.65),
                                Color(red: 0.15, green: 0.42, blue: 0.88),
                                Color(red: 0.48, green: 0.18, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            if let t = document.updatedAt {
                Text("Updated \(t.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var historyEntries: [CanvasHistory.Entry] {
        _ = refreshTick
        return CanvasHistory.list(address: address)
    }

    /// Sized so a short history fits without an inner scrollbar; longer lists scroll inside.
    private var historyTableHeight: CGFloat {
        let header: CGFloat = 30
        let row: CGFloat = 28
        let maxVisible = 8
        let n = min(max(historyEntries.count, 1), maxVisible)
        return header + CGFloat(n) * row
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(.headline)
                Spacer(minLength: 8)
                if !historyEntries.isEmpty {
                    Text("\(historyEntries.count)/\(CanvasHistory.maxEntries)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if historyEntries.isEmpty {
                Text("No previous versions yet. Updates from agents and Clear/Seed will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Table(historyEntries) {
                    TableColumn("When") { entry in
                        Text(compactHistoryDate(entry.savedAt))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(ideal: 108, max: 120)

                    TableColumn("Title") { entry in
                        Text(historyTitle(entry))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(historyTitle(entry))
                    }
                    // Flexible middle column — no min width that forces horizontal scroll.

                    TableColumn("Source") { entry in
                        Text(entry.source.displayName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(ideal: 64, max: 72)

                    TableColumn("") { entry in
                        Menu {
                            Button("Restore") {
                                restoreHistory(entry)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteHistory(entry)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("Version actions")
                        .accessibilityLabel("Version actions")
                    }
                    .width(36)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(height: historyTableHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyTitle(_ entry: CanvasHistory.Entry) -> String {
        if let t = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return "Untitled"
    }

    private func compactHistoryDate(_ date: Date) -> String {
        // Compact so the When column stays narrow on default window width.
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.year(.twoDigits).month(.abbreviated).day())
    }

    private func restoreHistory(_ entry: CanvasHistory.Entry) {
        do {
            try CanvasHistory.restore(address: address, entryId: entry.id)
            reloadWatcher.syncLastSeen(address: address)
            statusNote = "Restored version from \(entry.savedAt.formatted(date: .abbreviated, time: .shortened))"
            reloadWatcher.refreshCanvasCounts()
        } catch {
            statusNote = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func deleteHistory(_ entry: CanvasHistory.Entry) {
        do {
            try CanvasHistory.delete(address: address, entryId: entry.id)
            statusNote = "Deleted history entry"
        } catch {
            statusNote = "Delete failed: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// Main-area controls once published (link + auto-push). Publish/Unpublish live in the menu.
    private func publishedMainBlock(_ share: CloudShareRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Published")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
            HStack(spacing: 8) {
                badge(
                    share.resolvedVisibility == "org" ? "Organization" : "Public",
                    color: share.resolvedVisibility == "org" ? .purple : .blue
                )
                if let name = share.orgName ?? organizations.first(where: { $0.id == share.orgId })?.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Push updates when this canvas changes", isOn: $autoPushUpdates)
                .onChange(of: autoPushUpdates) { _, on in
                    try? CloudShareIndex.setAutoPush(canvas: address.rawValue, enabled: on)
                }
            HStack {
                Button("Push update now") {
                    Task { await pushUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || document.isEmptyContent)
            }
            if let publishError, !publishError.isEmpty {
                Text(publishError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    /// Main-area controls once subscribed (poll + refresh). Subscribe/Unsubscribe live in the menu.
    private func subscribedMainBlock(_ sub: CloudSubscription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscribed")
                .font(.headline)
            Text(sub.url)
                .font(.caption.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            HStack {
                Toggle("Enabled", isOn: $subEnabled)
                    .onChange(of: subEnabled) { _, _ in saveSubscription() }
                Text("Poll every")
                TextField("60", value: $subPoll, format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveSubscription() }
                Text("seconds")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { saveSubscription() }
                Button("Refresh now") {
                    Task { await fetchNow() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var publishSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Publish canvas")
                .font(.title2.weight(.semibold))
            Text("Share \(address.rawValue) to canvas cloud.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !oauth.isSignedIn {
                Text("Must sign in to publish.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Sign in with Velox…") {
                    Task {
                        do {
                            try await oauth.signIn(
                                config: cloudConfig,
                                presentingWindow: NSApp.keyWindow
                            )
                            await loadOrganizations()
                        } catch {
                            publishError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(oauth.isBusy)
            } else {
                Picker("Visibility", selection: $publishVisibility) {
                    ForEach(CloudAPIClient.PublishVisibility.allCases) { vis in
                        Text(vis.label).tag(vis)
                    }
                }
                .pickerStyle(.segmented)

                if publishVisibility == .org {
                    if orgsLoading {
                        ProgressView().controlSize(.small)
                    } else if let orgsError, !orgsError.isEmpty {
                        Text(orgsError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") {
                            Task { await loadOrganizations() }
                        }
                    } else if organizations.isEmpty {
                        Text("No organizations found for this account.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if organizations.count == 1, let only = organizations.first {
                        Text("Organization: \(only.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Organization", selection: Binding(
                            get: { selectedOrgId ?? organizations.first?.id ?? "" },
                            set: { selectedOrgId = $0 }
                        )) {
                            ForEach(organizations) { org in
                                Text(org.name).tag(org.id)
                            }
                        }
                    }
                }

                TextField("slug (optional)", text: $publishSlug)
                    .textFieldStyle(.roundedBorder)
            }

            if let publishError, !publishError.isEmpty {
                Text(publishError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { showPublishSheet = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                Button(busy ? "Publishing…" : "Publish") {
                    Task { await publish() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    busy
                        || !oauth.isSignedIn
                        || document.isEmptyContent
                        || (publishVisibility == .org
                            && (selectedOrgId ?? organizations.first?.id) == nil)
                )
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var subscribeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscribe")
                .font(.title2.weight(.semibold))
            Text("Pull JSON into \(address.rawValue) from a canvas API URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Feed URL (…/api/v1/canvases/{slug})", text: $subURL)
                .textFieldStyle(.roundedBorder)
            if let subError, !subError.isEmpty {
                Text(subError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { showSubscribeSheet = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                Button(busy ? "Subscribing…" : "Subscribe") {
                    Task { await subscribeFromSheet() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || subURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    @MainActor
    private func loadOrganizations() async {
        guard oauth.isSignedIn else { return }
        orgsLoading = true
        orgsError = nil
        defer { orgsLoading = false }
        do {
            let result = try await CloudAPIClient.listOrganizations(config: cloudConfig)
            organizations = result.organizations
            orgsError = nil
            if selectedOrgId == nil || !result.organizations.contains(where: { $0.id == selectedOrgId }) {
                selectedOrgId = result.activeOrganizationId
                    ?? result.organizations.first?.id
            }
        } catch {
            organizations = []
            orgsError = CloudAPIClient.userFacingMessage(for: error)
            NSLog("AgentCanvas: list organizations: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func publish() async {
        guard subscription == nil else {
            publishError = "Unsubscribe before publishing."
            return
        }
        busy = true
        publishError = nil
        defer { busy = false }
        do {
            try cloudConfig.save()
            let orgId: String?
            let orgName: String?
            if publishVisibility == .org {
                orgId = selectedOrgId ?? organizations.first?.id
                orgName = organizations.first(where: { $0.id == orgId })?.name
            } else {
                orgId = nil
                orgName = nil
            }
            let result = try await CloudAPIClient.publish(
                address: address,
                slug: publishSlug.isEmpty ? nil : publishSlug,
                visibility: publishVisibility,
                orgId: orgId,
                orgName: orgName,
                config: cloudConfig
            )
            publishSlug = result.slug
            lastPublicURL = result.publicURL
            autoPushUpdates = CloudShareIndex.record(forCanvas: address.rawValue)?.resolvedAutoPush ?? false
            showPublishSheet = false
            statusNote = "Published \(result.slug)"
        } catch {
            publishError = CloudAPIClient.userFacingMessage(for: error)
        }
    }

    @MainActor
    private func pushUpdate() async {
        busy = true
        publishError = nil
        defer { busy = false }
        do {
            let result = try await CloudAPIClient.updateShared(address: address, config: cloudConfig)
            lastPublicURL = result.publicURL
            statusNote = "Updated \(result.slug)"
        } catch {
            publishError = CloudAPIClient.userFacingMessage(for: error)
        }
    }

    @MainActor
    private func unshare() async {
        busy = true
        publishError = nil
        defer { busy = false }
        do {
            try await CloudAPIClient.unshare(
                slugOrCanvas: share?.slug ?? address.rawValue,
                config: cloudConfig
            )
            lastPublicURL = ""
            publishSlug = ""
            statusNote = "Unpublished"
        } catch {
            publishError = CloudAPIClient.userFacingMessage(for: error)
            statusNote = publishError ?? "Unpublish failed"
        }
    }

    private func unsubscribeKeepingContent() {
        do {
            try CloudSubscriptionStore.remove(canvas: address.rawValue)
            subURL = ""
            subError = nil
            statusNote = "Unsubscribed — local content kept"
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
            lastError: subscription?.lastError,
            lastStatusCode: subscription?.lastStatusCode
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
    private func subscribeFromSheet() async {
        guard share == nil else {
            subError = "Unpublish before subscribing."
            return
        }
        let url = subURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else {
            subError = "Enter a valid URL"
            return
        }
        busy = true
        subError = nil
        defer { busy = false }
        subEnabled = true
        let sub = CloudSubscription(
            canvas: address.rawValue,
            url: url,
            pollIntervalSeconds: max(15, subPoll),
            enabled: true,
            etag: nil,
            lastFetchAt: nil,
            lastError: nil,
            lastStatusCode: nil
        )
        do {
            try CloudSubscriptionStore.upsert(sub)
            try await CloudAPIClient.fetchSubscription(sub)
            showSubscribeSheet = false
            statusNote = "Subscribed \(address.rawValue)"
            reloadWatcher.noteManualReload()
        } catch {
            subError = CloudAPIClient.userFacingMessage(for: error)
        }
    }

    @MainActor
    private func fetchNow() async {
        busy = true
        defer { busy = false }
        guard let sub = subscription else { return }
        do {
            try await CloudAPIClient.fetchSubscription(sub)
            statusNote = "Fetched into \(address.rawValue)"
            reloadWatcher.noteManualReload()
        } catch {
            statusNote = error.localizedDescription
        }
    }
    #endif
}

// MARK: - Subscribe deep link (PLAT-105)

#if DEBUG
private struct SubscribeSlugRequest: Identifiable {
    var id: String { slug }
    let slug: String
}

/// Slot picker for `agentcanvas://subscribe?slug=…` from Canvas web.
private struct SubscribeDeepLinkSheet: View {
    let slug: String
    var onComplete: (CanvasAddress) -> Void
    var onCancel: () -> Void

    @State private var selected: CanvasAddress = .mdOne
    @State private var busy = false
    @State private var errorText: String?
    @ObservedObject private var oauth = VeloxOAuthSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscribe to canvas")
                .font(.title2.weight(.semibold))
            Text("Pull “\(slug)” into a local slot.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Slot", selection: $selected) {
                ForEach(CanvasAddress.allCases) { address in
                    Text("\(address.displayName) (\(address.rawValue))")
                        .tag(address)
                }
            }
            .pickerStyle(.menu)

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                Button(busy ? "Subscribing…" : "Subscribe") {
                    Task { await subscribe() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @MainActor
    private func subscribe() async {
        busy = true
        errorText = nil
        defer { busy = false }

        #if DEBUG
        CloudFeature.userToggleEnabled = true
        #endif

        let config = CloudConfigStore.load()
        guard let url = config.canvasURL(slug: slug)?.absoluteString else {
            errorText = "Invalid API base URL."
            return
        }

        let sub = CloudSubscription(
            canvas: selected.rawValue,
            url: url,
            pollIntervalSeconds: max(15, config.defaultPollIntervalSeconds),
            enabled: true,
            etag: nil,
            lastFetchAt: nil,
            lastError: nil,
            lastStatusCode: nil
        )

        do {
            try CloudSubscriptionStore.upsert(sub)
            try await fetchWithAuthRetry(sub)
            onComplete(selected)
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func fetchWithAuthRetry(_ sub: CloudSubscription) async throws {
        do {
            try await CloudAPIClient.fetchSubscription(sub)
        } catch {
            let needsSignIn = !oauth.isSignedIn
                && (error.localizedDescription.localizedCaseInsensitiveContains("sign in")
                    || (CloudSubscriptionStore.subscription(for: sub.canvas)?.lastStatusCode == 401)
                    || (CloudSubscriptionStore.subscription(for: sub.canvas)?.lastStatusCode == 403))
            guard needsSignIn else { throw error }
            try await oauth.signIn(config: CloudConfigStore.load(), presentingWindow: NSApp.keyWindow)
            try await CloudAPIClient.fetchSubscription(sub)
        }
    }
}
#endif

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

