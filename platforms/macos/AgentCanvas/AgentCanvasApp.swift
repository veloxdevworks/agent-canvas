import SwiftUI
import WidgetKit
import AppKit

@main
struct AgentCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var reloadWatcher: ReloadWatcher { appDelegate.reloadWatcher }

    var body: some Scene {
        // Optional windows — not required for the host to stay alive.
        Window("Agent Canvas", id: "main") {
            SettingsView()
                .environmentObject(reloadWatcher)
        }
        .defaultSize(width: 900, height: 620)
        .handlesExternalEvents(matching: [])
        .commands {
            AgentCanvasCommands(reloadWatcher: reloadWatcher)
        }

        Window("Connect agent", id: "connect-wizard") {
            ConnectWizardView()
                .environmentObject(reloadWatcher)
        }
        .defaultSize(width: 600, height: 620)
        .handlesExternalEvents(matching: [])

        Window("Seed demos", id: "seed") {
            SeedDemosView()
                .environmentObject(reloadWatcher)
        }
        .defaultSize(width: 640, height: 680)
        .handlesExternalEvents(matching: [])

        // Claims `agentcanvas://detail…` so widget taps don't fall through to Settings.
        WindowGroup("Detail", id: "detail", for: String.self) { $id in
            DetailWindowRoot(id: $id)
                .environmentObject(reloadWatcher)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "detail"))
        .defaultSize(width: 500, height: 700)

        // Primary UI: menu bar agent. Survives with zero open windows.
        // Custom concentric-frame glyph (template) — not the SF Symbol grid.
        MenuBarExtra {
            // Do not inject environmentObject here — live observation dismisses submenus.
            MenuBarExtraView()
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        CanvasStorage.ensureDirectories()
    }
}

struct MenuBarLabelView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text("Agent Canvas")
        } icon: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Agent Canvas")
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenDetail)) { notification in
            // Widget URLs already spawn Detail via handlesExternalEvents — only openWindow
            // for in-app requests to avoid a second empty detail window.
            let fromURL = (notification.userInfo?["fromURL"] as? Bool) == true
            if let id = notification.object as? String, !fromURL {
                openWindow(id: "detail", value: id)
            }
            DispatchQueue.main.async {
                AppDelegate.hideSettingsWindows()
            }
        }
    }
}

/// Root for the typed detail WindowGroup — binds canvas id from openWindow or widget URL.
private struct DetailWindowRoot: View {
    @Binding var id: String?

    var body: some View {
        Group {
            if let id, let address = CanvasAddress(rawValue: id) {
                CanvasDetailWindowView(address: address)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear {
            applyPendingDetailIdIfNeeded()
        }
        .onOpenURL { url in
            if let newId = AppDelegate.canvasId(fromDetailURL: url) {
                id = newId
                AppDelegate.pendingDetailId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenDetail)) { notification in
            if let newId = notification.object as? String {
                id = newId
                AppDelegate.pendingDetailId = nil
            }
        }
    }

    private func applyPendingDetailIdIfNeeded() {
        guard id == nil, let pending = AppDelegate.pendingDetailId else { return }
        id = pending
        AppDelegate.pendingDetailId = nil
    }
}

extension Notification.Name {
    static let agentCanvasShowHowTo = Notification.Name("agentCanvasShowHowTo")
    static let agentCanvasOpenConnect = Notification.Name("agentCanvasOpenConnect")
    static let agentCanvasOpenSeed = Notification.Name("agentCanvasOpenSeed")
    static let agentCanvasOpenCloud = Notification.Name("agentCanvasOpenCloud")
    static let agentCanvasOpenDetail = Notification.Name("agentCanvasOpenDetail")
    /// Show connect wizard client picker (not a specific client flow).
    static let agentCanvasConnectShowLanding = Notification.Name("agentCanvasConnectShowLanding")
}

/// App menu commands with `openWindow` access.
struct AgentCanvasCommands: Commands {
    @ObservedObject var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("How to Use…") {
                openWindow(id: "main")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .agentCanvasShowHowTo, object: nil)
                }
            }
            Button("Connect Agent…") {
                reloadWatcher.preferredConnectClient = .cursor
                openWindow(id: "connect-wizard")
            }
        }

        CommandMenu("Developer") {
            Button("Seed Demos…") {
                openWindow(id: "seed")
            }
            #if DEBUG
            Button("Cloud settings…") {
                openWindow(id: "main")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .agentCanvasOpenCloud, object: nil)
                }
            }
            #endif
            Button("Reload All Widgets") {
                CanvasStorage.mirrorAllAndReload()
                reloadWatcher.noteManualReload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open Data Folder") {
                CanvasStorage.ensureDirectories()
                NSWorkspace.shared.open(CanvasStorage.applicationSupportRoot)
            }
            Button("Copy Diagnostics") {
                UserGuide.copyDiagnostics()
            }
            Button("Reset Onboarding Flags") {
                UserGuide.resetOnboardingFlags()
                reloadWatcher.setStatusLine(
                    "Onboarding flags reset — reopen Agent Canvas to see checklist"
                )
            }
        }
    }
}

/// Polls `~/.velox/canvas` for MCP `.reload-request` and reloads WidgetKit.
@MainActor
final class ReloadWatcher: ObservableObject {
    @Published var lastReload: Date?
    @Published var statusLine: String = "Watching for agent updates…"
    @Published var isWatching: Bool = false
    @Published var filledCount: Int = 0
    @Published var totalCount: Int = CanvasAddress.allCases.count
    @Published var preferredConnectClient: ConnectWizardClient = .cursor

    private var timer: Timer?
    private var started = false
    /// Last poll time per canvas id for cloud subscriptions.
    private var lastSubscriptionPoll: [String: Date] = [:]

    var canvasFillSummary: String {
        "\(filledCount)/\(totalCount) filled"
    }

    func start() {
        guard !started else { return }
        started = true
        HostRuntime.reloadWatcher = self
        CanvasStorage.ensureDirectories()
        CanvasStorage.mirrorAllAndReload()
        refreshCanvasCounts()
        isWatching = true
        setStatusLine("Watching for agent updates…")

        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func noteManualReload() {
        lastReload = Date()
        setStatusLine(
            "Manual reload at \(lastReload!.formatted(date: .omitted, time: .standard))"
        )
        refreshCanvasCounts()
    }

    func refreshCanvasCounts() {
        let filled = CanvasAddress.allCases.filter {
            !CanvasStorage.load(address: $0).isEmptyContent
        }.count
        let total = CanvasAddress.allCases.count
        if filledCount != filled { filledCount = filled }
        if totalCount != total { totalCount = total }
    }

    func setStatusLine(_ line: String) {
        if statusLine != line { statusLine = line }
    }

    func diagnosticsReport() -> String {
        refreshCanvasCounts()
        let mcp = AgentCanvasPaths.mcpBinaryResolved()
        var lines: [String] = [
            "Agent Canvas diagnostics",
            "version: \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))",
            "macos: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "watching: \(isWatching)",
            "canvases: \(canvasFillSummary)",
            "lastReload: \(lastReload?.description ?? "never")",
            "status: \(statusLine)",
            "dataRoot: \(CanvasStorage.applicationSupportRoot.path)",
            "mcpBinary: \(mcp.path)",
            "mcpExists: \(mcp.exists)",
            "cursorInstalled: \(MCPClientInstall.isCursorInstalled())",
            "cursorRegistered: \(MCPClientInstall.isRegisteredInCursor())",
            "claudeInstalled: \(MCPClientInstall.isClaudeDesktopInstalled())",
            "claudeRegistered: \(MCPClientInstall.isRegisteredInClaude())",
            "",
            "canvases:",
        ]
        for address in CanvasAddress.allCases {
            let doc = CanvasStorage.load(address: address)
            let title = doc.title ?? "—"
            let n = doc.sections.count
            let empty = doc.isEmptyContent ? "empty" : "ok"
            lines.append("  \(address.rawValue): \(empty) sections=\(n) title=\(title)")
        }
        return lines.joined(separator: "\n")
    }

    private func tick() {
        if !isWatching { isWatching = true }

        if let preview = CanvasStorage.consumePreviewRequest() {
            let result = CanvasPreviewRenderer.render(request: preview)
            lastReload = Date()
            if result.ok {
                setStatusLine(
                    "Preview \(preview.address.rawValue) ready at \(lastReload!.formatted(date: .omitted, time: .standard))"
                )
            } else {
                setStatusLine(
                    "Preview \(preview.address.rawValue) failed: \(result.error ?? "unknown")"
                )
            }
        }

        if let request = CanvasStorage.consumeReloadRequest() {
            switch request {
            case .one(let address):
                CanvasStorage.reload(address: address)
                lastReload = Date()
                setStatusLine(
                    "Reloaded \(address.displayName) (\(address.rawValue)) at \(lastReload!.formatted(date: .omitted, time: .standard))"
                )
            case .all:
                CanvasStorage.reloadAllTimelines()
                lastReload = Date()
                setStatusLine(
                    "Reloaded all widgets at \(lastReload!.formatted(date: .omitted, time: .standard))"
                )
            }
            refreshCanvasCounts()
        }

        pollCloudSubscriptionsIfNeeded()
    }

    /// PLAT-83-lite: when cloud feature is on, poll enabled URL subscriptions.
    private func pollCloudSubscriptionsIfNeeded() {
        guard CloudFeature.isEnabled else { return }
        let now = Date()
        for sub in CloudSubscriptionStore.load() where sub.enabled {
            let interval = TimeInterval(max(15, sub.pollIntervalSeconds))
            if let last = lastSubscriptionPoll[sub.canvas],
               now.timeIntervalSince(last) < interval
            {
                continue
            }
            lastSubscriptionPoll[sub.canvas] = now
            let captured = sub
            Task { @MainActor in
                do {
                    try await CloudAPIClient.fetchSubscription(captured)
                    self.setStatusLine("Synced subscription \(captured.canvas)")
                    self.refreshCanvasCounts()
                } catch {
                    NSLog(
                        "AgentCanvas: subscription \(captured.canvas): \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

/// Non-observing access for MenuBarExtra (avoids menu rebuild / submenu dismiss).
@MainActor
enum HostRuntime {
    static weak var reloadWatcher: ReloadWatcher?

    static var watcher: ReloadWatcher? { reloadWatcher }
}

/// Menu-bar agent lifecycle: stay running with zero windows.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Canvas id from a widget URL, consumed when DetailWindowRoot appears.
    static var pendingDetailId: String?

    /// Owned here so the host lives independent of any SwiftUI window.
    private var watcherStorage: ReloadWatcher?

    @MainActor
    var reloadWatcher: ReloadWatcher {
        if let watcherStorage { return watcherStorage }
        let w = ReloadWatcher()
        watcherStorage = w
        return w
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory = menu bar agent: survives with no open windows (and no Dock icon).
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            let watcher = self.reloadWatcher
            HostRuntime.reloadWatcher = watcher
            watcher.start()
        }

        // SwiftUI may open a default Window at launch — hide it so we start menu-bar-only.
        DispatchQueue.main.async {
            Self.hideContentWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.hideContentWindows()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if VeloxOAuthSession.isOAuthCallback(url) {
                Task { @MainActor in
                    VeloxOAuthSession.shared.handleCallbackURL(url)
                }
            } else if let id = Self.canvasId(fromDetailURL: url) {
                // Detail WindowGroup claims the URL (handlesExternalEvents). Stash + notify
                // so the new scene can bind its canvas id even if it appears after this.
                Self.pendingDetailId = id
                NotificationCenter.default.post(
                    name: .agentCanvasOpenDetail,
                    object: id,
                    userInfo: ["fromURL": true]
                )
                DispatchQueue.main.async {
                    Self.hideSettingsWindows()
                    NSApp.activate(ignoringOtherApps: true)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Self.hideSettingsWindows()
                }
            }
        }
    }

    static func canvasId(fromDetailURL url: URL) -> String? {
        guard url.scheme == "agentcanvas", url.host == "detail" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "id" })?.value
    }

    /// Settings scene title is "Agent Canvas"; never hide Detail / wizard / seed.
    static func hideSettingsWindows() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("StatusBar") || className.contains("NSStatusBar") {
                continue
            }
            if window.title == "Agent Canvas" {
                window.orderOut(nil)
            }
        }
    }

    private static func hideContentWindows() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("StatusBar") || className.contains("NSStatusBar") {
                continue
            }
            if window.frame.width < 2 || window.frame.height < 2 {
                continue
            }
            if window.canBecomeMain || !window.title.isEmpty {
                window.orderOut(nil)
            }
        }
    }
}
