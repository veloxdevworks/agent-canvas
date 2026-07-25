import SwiftUI
import AppKit

/// Debug-gated cloud publish + URL subscription UI (PLAT-82/83 prep).
struct CloudSettingsView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher

    @State private var config = CloudConfigStore.load()
    @State private var toggleEnabled = CloudFeature.userToggleEnabled
    @State private var shares: [CloudShareRecord] = []
    @State private var subscriptions: [CloudSubscription] = []
    @State private var statusNote = ""
    @State private var busy = false

    @State private var publishCanvas: CanvasAddress = .mdOne
    @State private var publishSlug = ""
    @State private var lastPublicURL = ""

    @State private var subCanvas: CanvasAddress = .mdTwo
    @State private var subURL = ""
    @State private var subPoll = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                enableSection
                apiSection
                if CloudFeature.isEnabled {
                    publishSection
                    sharesSection
                    subscribeSection
                    subscriptionsList
                } else {
                    Text("Turn on “Enable cloud features (debug)” above, or launch with \(CloudFeature.envName)=1, to show publish and subscribe.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer(minLength: 8)
                Text(statusNote.isEmpty ? " " : statusNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear(perform: reloadLocal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cloud")
                .font(.largeTitle.bold())
            Text("Publish canvases and bind slots to a public JSON URL. Pre-release — debug only.")
                .foregroundStyle(.secondary)
            Text(CloudFeature.statusDescription)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private var enableSection: some View {
        GroupBox("Access") {
            VStack(alignment: .leading, spacing: 10) {
                #if DEBUG
                Toggle("Enable cloud features (debug)", isOn: $toggleEnabled)
                    .onChange(of: toggleEnabled) { _, on in
                        CloudFeature.userToggleEnabled = on
                        statusNote = on
                            ? "Cloud UI enabled (Settings toggle)"
                            : "Cloud UI disabled"
                    }
                Text("Also enabled when process env \(CloudFeature.envName)=1. Release builds never enable this UI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("Cloud UI is compiled out of Release builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var apiSection: some View {
        GroupBox("API") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Canvas cloud base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://canvas.velox.test", text: $config.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Default poll interval (seconds)")
                    TextField("60", value: $config.defaultPollIntervalSeconds, format: .number)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Save API settings") {
                        do {
                            try config.save()
                            statusNote = "Saved \(config.normalizedAPIBase)"
                        } catch {
                            statusNote = "Save failed: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset to default") {
                        config.apiBaseURL = CloudConfigStore.defaultAPIBase
                        config.defaultPollIntervalSeconds = CloudConfigStore.defaultPoll
                    }
                }
            }
            .padding(4)
        }
    }

    private var publishSection: some View {
        GroupBox("Publish") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Canvas", selection: $publishCanvas) {
                        ForEach(CanvasAddress.allCases) { a in
                            Text("\(a.displayName) (\(a.rawValue))").tag(a)
                        }
                    }
                    TextField("slug (optional)", text: $publishSlug)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                }
                HStack {
                    Button("Publish / share") {
                        Task { await publish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    Button("Push update") {
                        Task { await pushUpdate() }
                    }
                    .disabled(busy)
                    Button("Unshare") {
                        Task { await unshareSelected() }
                    }
                    .disabled(busy)
                }
                if !lastPublicURL.isEmpty {
                    HStack {
                        Text(lastPublicURL)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lastPublicURL, forType: .string)
                            statusNote = "Public URL copied"
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private var sharesSection: some View {
        GroupBox("Published from this Mac") {
            if shares.isEmpty {
                Text("No local share records yet.")
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shares) { s in
                        HStack {
                            Text(s.canvas)
                                .font(.caption.monospaced())
                            Text("→")
                            Text(s.slug)
                                .fontWeight(.medium)
                            Spacer()
                            Text(CloudKeychain.getToken(slug: s.slug) != nil ? "token ✓" : "no token")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Button("Copy link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(s.publicUrl, forType: .string)
                                statusNote = "Copied \(s.publicUrl)"
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private var subscribeSection: some View {
        GroupBox("Subscribe slot to URL") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Binds a desktop canvas id to a JSON feed (usually …/api/v1/canvases/{slug}). Polling daemon is minimal: use Fetch now, or wait for host pull in a later build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("Canvas", selection: $subCanvas) {
                        ForEach(CanvasAddress.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    TextField("Feed URL", text: $subURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("poll s", value: $subPoll, format: .number)
                        .frame(width: 56)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Save subscription") {
                        saveSubscription()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Fetch now") {
                        Task { await fetchNow() }
                    }
                    .disabled(busy)
                }
            }
            .padding(4)
        }
    }

    private var subscriptionsList: some View {
        GroupBox("Subscriptions") {
            if subscriptions.isEmpty {
                Text("None.")
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(subscriptions) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Toggle("", isOn: bindingEnabled(for: s))
                                    .labelsHidden()
                                Text(s.canvas)
                                    .font(.caption.monospaced().weight(.semibold))
                                Text("every \(s.pollIntervalSeconds)s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Fetch") {
                                    Task { await fetch(s) }
                                }
                                .disabled(busy)
                                Button("Remove", role: .destructive) {
                                    try? CloudSubscriptionStore.remove(canvas: s.canvas)
                                    reloadLocal()
                                }
                            }
                            Text(s.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let err = s.lastError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            } else if let at = s.lastFetchAt {
                                Text("Last fetch \(at.formatted())")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Divider()
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Actions

    private func reloadLocal() {
        config = CloudConfigStore.load()
        toggleEnabled = CloudFeature.userToggleEnabled
        shares = CloudShareIndex.load()
        subscriptions = CloudSubscriptionStore.load()
        if subPoll < 15 { subPoll = config.defaultPollIntervalSeconds }
    }

    private func bindingEnabled(for sub: CloudSubscription) -> Binding<Bool> {
        Binding(
            get: { CloudSubscriptionStore.subscription(for: sub.canvas)?.enabled ?? sub.enabled },
            set: { on in
                var s = sub
                s.enabled = on
                try? CloudSubscriptionStore.upsert(s)
                reloadLocal()
            }
        )
    }

    @MainActor
    private func publish() async {
        busy = true
        defer { busy = false }
        do {
            try config.save()
            let result = try await CloudAPIClient.publish(
                address: publishCanvas,
                slug: publishSlug.isEmpty ? nil : publishSlug,
                config: config
            )
            lastPublicURL = result.publicURL
            statusNote = "Published \(result.slug) — token stored in Keychain"
            reloadLocal()
            reloadWatcher.setStatusLine("Published \(result.slug)")
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func pushUpdate() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await CloudAPIClient.updateShared(address: publishCanvas, config: config)
            lastPublicURL = result.publicURL
            statusNote = "Updated \(result.slug) (v\(result.version.map(String.init) ?? "?"))"
            reloadLocal()
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func unshareSelected() async {
        busy = true
        defer { busy = false }
        do {
            let target = CloudShareIndex.record(forCanvas: publishCanvas.rawValue)?.slug
                ?? publishSlug
            guard !target.isEmpty else {
                statusNote = "No share for \(publishCanvas.rawValue)"
                return
            }
            try await CloudAPIClient.unshare(slugOrCanvas: target, config: config)
            lastPublicURL = ""
            statusNote = "Unshared \(target)"
            reloadLocal()
        } catch {
            statusNote = error.localizedDescription
        }
    }

    private func saveSubscription() {
        let url = subURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else {
            statusNote = "Enter a valid feed URL"
            return
        }
        let poll = max(15, subPoll)
        let sub = CloudSubscription(
            canvas: subCanvas.rawValue,
            url: url,
            pollIntervalSeconds: poll,
            enabled: true,
            etag: CloudSubscriptionStore.subscription(for: subCanvas.rawValue)?.etag,
            lastFetchAt: CloudSubscriptionStore.subscription(for: subCanvas.rawValue)?.lastFetchAt,
            lastError: nil,
            lastStatusCode: nil
        )
        do {
            try CloudSubscriptionStore.upsert(sub)
            try config.save()
            statusNote = "Subscription saved for \(subCanvas.rawValue)"
            reloadLocal()
        } catch {
            statusNote = error.localizedDescription
        }
    }

    @MainActor
    private func fetchNow() async {
        guard let sub = CloudSubscriptionStore.subscription(for: subCanvas.rawValue)
            ?? (subURL.isEmpty ? nil : CloudSubscription(
                canvas: subCanvas.rawValue,
                url: subURL,
                pollIntervalSeconds: max(15, subPoll),
                enabled: true
            ))
        else {
            statusNote = "Save a subscription first"
            return
        }
        await fetch(sub)
    }

    @MainActor
    private func fetch(_ sub: CloudSubscription) async {
        busy = true
        defer { busy = false }
        do {
            try await CloudAPIClient.fetchSubscription(sub)
            statusNote = "Fetched into \(sub.canvas)"
            reloadWatcher.noteManualReload()
            reloadLocal()
        } catch {
            statusNote = error.localizedDescription
            reloadLocal()
        }
    }
}
