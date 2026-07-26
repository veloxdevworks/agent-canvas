import SwiftUI
import AppKit

// MARK: - Connect wizard (first-class client setup)

/// Guided, decision-tree setup for one MCP client at a time.
/// Landing shows client choice; once a path starts, only that client's steps appear.
struct ConnectWizardView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.dismiss) private var dismiss

    /// `nil` = pick-a-client landing. Set when user commits to a flow.
    @State private var activeClient: ConnectWizardClient?
    @State private var stepID: String = ""
    @State private var mcpPath = AgentCanvasPaths.preferredMCPBinaryPath()
    @State private var mcpExists = false
    @State private var cursorRegistered = false
    @State private var claudeRegistered = false
    @State private var claudeRunning = false
    @State private var cursorInstalled = false
    @State private var claudeInstalled = false
    @State private var statusMessage: String?
    @State private var statusTone: StatusTone = .neutral
    @State private var pollTimer: Timer?

    private enum StatusTone {
        case neutral, good, warn, bad
        var color: Color {
            switch self {
            case .neutral: return .secondary
            case .good: return .green
            case .warn: return .orange
            case .bad: return .red
            }
        }
    }

    init(client: ConnectWizardClient? = nil) {
        // Prefer explicit client; landing if nil.
        _activeClient = State(initialValue: client)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let client = activeClient {
                clientFlow(client)
            } else {
                landing
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Menu sets preferredConnectClient then opens this window → jump into that flow.
            if activeClient == nil {
                activeClient = reloadWatcher.preferredConnectClient
            }
            enterFirstStep()
            refreshState()
            startPollingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasConnectShowLanding)) { _ in
            activeClient = nil
            stepID = ""
            statusMessage = nil
            refreshState()
        }
        .onChange(of: reloadWatcher.preferredConnectClient) { _, newValue in
            activeClient = newValue
            enterFirstStep()
            refreshState()
            statusMessage = nil
        }
        .onChange(of: activeClient) { _, _ in
            startPollingIfNeeded()
        }
        .onChange(of: stepID) { _, _ in
            startPollingIfNeeded()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Landing (pick client)

    private var landing: some View {
        VStack(spacing: 0) {
            heroArtwork(
                symbol: "link.circle.fill",
                accent: .accentColor,
                showBack: false,
                progress: nil,
                onBack: {}
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your agent")
                        .font(.title2.weight(.bold))
                    Text("Pick the app you chat with. We’ll walk through the exact steps for that app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Which app do you use?")
                        .font(.headline)
                        .padding(.top, 8)

                    clientChoiceCard(
                        client: .cursor,
                        blurb: MCPClientInstall.isConnected(.cursor)
                            ? "Already connected — open to manage or re-run setup."
                            : "Fastest setup — opens Cursor’s install dialog.",
                        badge: MCPClientInstall.isConnected(.cursor)
                            ? "Connected"
                            : (MCPClientInstall.isCursorInstalled() ? "Installed" : nil)
                    )
                    clientChoiceCard(
                        client: .claude,
                        blurb: MCPClientInstall.isConnected(.claude)
                            ? "Already connected — open to manage or re-run setup."
                            : "We’ll quit Claude if needed, then write its config safely.",
                        badge: MCPClientInstall.isConnected(.claude)
                            ? "Connected"
                            : (MCPClientInstall.isClaudeDesktopInstalled() ? "Installed" : nil)
                    )
                    clientChoiceCard(
                        client: .chatgpt,
                        blurb: "ChatGPT can’t use a local agent yet — we’ll explain options.",
                        badge: "Limited"
                    )
                    clientChoiceCard(
                        client: .manual,
                        blurb: "Copy a config snippet for another MCP-compatible app.",
                        badge: nil
                    )
                }
                .padding(24)
            }
        }
        .onAppear { applyWindowTitle(nil) }
    }

    private func clientChoiceCard(client: ConnectWizardClient, blurb: String, badge: String?) -> some View {
        Button {
            activeClient = client
            reloadWatcher.preferredConnectClient = client
            enterFirstStep()
            refreshState()
            statusMessage = nil
        } label: {
            HStack(spacing: 14) {
                Image(systemName: client.symbolName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(client.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(client.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Client flow shell

    private func clientFlow(_ client: ConnectWizardClient) -> some View {
        let step = currentStep(for: client)
        return VStack(spacing: 0) {
            heroArtwork(
                symbol: step.heroSymbol ?? client.symbolName,
                accent: client.accent,
                showBack: canGoBack(for: client),
                progress: stepProgress(for: client),
                onBack: { goBack(for: client) }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(step.title)
                        .font(.title2.weight(.semibold))

                    Text(step.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let bullets = step.bullets, !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(bullets.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(client.accent)
                                        .font(.body)
                                    Text(line)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        }
                    }

                    statusChips(for: client, step: step)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(statusTone.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let primary = step.primary {
                            Button {
                                primary.handler()
                            } label: {
                                Text(primary.title)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(primary.disabled)
                            .keyboardShortcut(.defaultAction)
                        }
                        if let secondary = step.secondary {
                            Button {
                                secondary.handler()
                            } label: {
                                Text(secondary.title)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(secondary.disabled)
                        }
                        if let tertiary = step.tertiary {
                            Button(tertiary.title, action: tertiary.handler)
                                .buttonStyle(.borderless)
                                .disabled(tertiary.disabled)
                        }
                        if step.isTerminal {
                            Button {
                                UserGuide.hasCompletedOnboarding = true
                                dismiss()
                            } label: {
                                Text("Done")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { applyWindowTitle(client) }
        .onChange(of: stepID) { _, _ in applyWindowTitle(client) }
    }

    // MARK: - Hero / chrome

    /// Artwork only: back chevron (top-leading), step pill (top-trailing). No title strip.
    private func heroArtwork(
        symbol: String,
        accent: Color,
        showBack: Bool,
        progress: (current: Int, total: Int)?,
        onBack: @escaping () -> Void
    ) -> some View {
        ZStack {
            // Placeholder for future image / animated WebP / GIF
            LinearGradient(
                colors: [
                    accent.opacity(0.55),
                    accent.opacity(0.22),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                    Image(systemName: symbol)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityHidden(true)

                Text("Hero artwork placeholder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack {
                HStack(alignment: .center) {
                    if showBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Back")
                        .accessibilityLabel("Back")
                    }
                    Spacer(minLength: 8)
                    if let progress {
                        Text("Step \(progress.current) of \(progress.total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(14)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipped()
    }

    private func applyWindowTitle(_ client: ConnectWizardClient?) {
        let title: String
        if let client {
            title = "Connect from \(client.windowTitleName)"
        } else {
            title = "Connect agent"
        }
        for window in NSApp.windows {
            let t = window.title
            if t == "Connect agent" || t.hasPrefix("Connect from ") || t.isEmpty {
                // Prefer the connect wizard window (not tiny status chrome).
                if window.frame.width >= 400 {
                    window.title = title
                }
            }
        }
    }

    // MARK: - Status chips

    @ViewBuilder
    private func statusChips(for client: ConnectWizardClient, step: WizardStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            chip(
                ok: mcpExists,
                okText: "Agent helper ready",
                badText: "Agent helper not found — build it first (just build-rust)"
            )
            if client == .claude {
                if step.id == ClaudeStepID.quit.rawValue || step.id == ClaudeStepID.write.rawValue {
                    chip(
                        ok: !claudeRunning,
                        okText: "Claude is fully quit",
                        badText: "Claude is still running — quit it completely"
                    )
                }
                if step.id == ClaudeStepID.write.rawValue || step.id == ClaudeStepID.open.rawValue
                    || step.id == ClaudeStepID.done.rawValue
                {
                    chip(
                        ok: claudeRegistered,
                        okText: "Agent Canvas is in Claude’s settings file",
                        badText: "Not in Claude’s settings file yet"
                    )
                }
            }
            if client == .cursor {
                if step.id == CursorStepID.confirm.rawValue || step.id == CursorStepID.done.rawValue {
                    chip(
                        ok: cursorRegistered,
                        okText: "Listed in Cursor’s MCP config",
                        badText: "Not in Cursor’s config yet (confirm the install dialog)"
                    )
                }
            }
        }
    }

    private func chip(ok: Bool, okText: String, badText: String) -> some View {
        Label(ok ? okText : badText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    // MARK: - Step model

    private struct WizardAction {
        var title: String
        var disabled: Bool = false
        var handler: () -> Void
    }

    private struct WizardStep {
        var id: String
        var heroTitle: String
        var heroSubtitle: String
        var heroSymbol: String?
        var title: String
        var body: String
        var bullets: [String]?
        var primary: WizardAction?
        var secondary: WizardAction?
        var tertiary: WizardAction?
        var isTerminal: Bool = false
    }

    private enum ClaudeStepID: String, CaseIterable {
        case binary, install, quit, write, open, done
    }

    private enum CursorStepID: String, CaseIterable {
        case binary, install, confirm, done
    }

    private enum ChatGPTStepID: String, CaseIterable {
        case explain, options, done
    }

    private enum ManualStepID: String, CaseIterable {
        case binary, copy, paste, done
    }

    private func currentStep(for client: ConnectWizardClient) -> WizardStep {
        switch client {
        case .claude: return claudeStep()
        case .cursor: return cursorStep()
        case .chatgpt: return chatgptStep()
        case .manual: return manualStep()
        }
    }

    private func stepProgress(for client: ConnectWizardClient) -> (current: Int, total: Int)? {
        let ordered: [String]
        switch client {
        case .claude:
            ordered = resolvedClaudePath().map(\.rawValue)
        case .cursor:
            ordered = resolvedCursorPath().map(\.rawValue)
        case .chatgpt:
            ordered = ChatGPTStepID.allCases.map(\.rawValue)
        case .manual:
            ordered = resolvedManualPath().map(\.rawValue)
        }
        guard let idx = ordered.firstIndex(of: stepID) else { return nil }
        return (idx + 1, ordered.count)
    }

    // MARK: - Decision trees (path resolution)

    /// Only steps the user still needs — satisfied gates are omitted so progress starts at 1.
    private func resolvedClaudePath() -> [ClaudeStepID] {
        var path: [ClaudeStepID] = []
        if !mcpExists { path.append(.binary) }
        if !claudeInstalled { path.append(.install) }
        // Only require quit while Claude is running (or if user is already on that step).
        if claudeRunning || stepID == ClaudeStepID.quit.rawValue {
            path.append(.quit)
        }
        path.append(contentsOf: [.write, .open, .done])
        return path
    }

    private func resolvedCursorPath() -> [CursorStepID] {
        var path: [CursorStepID] = []
        if !mcpExists { path.append(.binary) }
        path.append(contentsOf: [.install, .confirm, .done])
        return path
    }

    private func resolvedManualPath() -> [ManualStepID] {
        var path: [ManualStepID] = []
        if !mcpExists { path.append(.binary) }
        path.append(contentsOf: [.copy, .paste, .done])
        return path
    }

    private func enterFirstStep() {
        guard let client = activeClient else {
            stepID = ""
            applyWindowTitle(nil)
            return
        }
        refreshState()
        // Already set up — jump to the done step so we don’t re-walk the wizard.
        if MCPClientInstall.isConnected(client) {
            switch client {
            case .claude:
                stepID = ClaudeStepID.done.rawValue
            case .cursor:
                stepID = CursorStepID.done.rawValue
            case .chatgpt, .manual:
                break
            }
            if client == .claude || client == .cursor {
                note("Already connected — you’re good to go", .good)
                applyWindowTitle(client)
                return
            }
        }
        switch client {
        case .claude:
            stepID = resolvedClaudePath().first?.rawValue ?? ClaudeStepID.write.rawValue
        case .cursor:
            stepID = resolvedCursorPath().first?.rawValue ?? CursorStepID.install.rawValue
        case .chatgpt:
            stepID = ChatGPTStepID.explain.rawValue
        case .manual:
            stepID = resolvedManualPath().first?.rawValue ?? ManualStepID.copy.rawValue
        }
        applyWindowTitle(client)
    }

    private func nextClaudeStep(from current: ClaudeStepID?) -> ClaudeStepID? {
        let path = resolvedClaudePath()
        guard let current else { return path.first }
        guard let i = path.firstIndex(of: current), i + 1 < path.count else { return nil }
        return path[i + 1]
    }

    private func prevClaudeStep(from current: ClaudeStepID) -> ClaudeStepID? {
        let path = resolvedClaudePath()
        guard let i = path.firstIndex(of: current), i > 0 else { return nil }
        return path[i - 1]
    }

    private func canGoBack(for client: ConnectWizardClient) -> Bool {
        switch client {
        case .claude:
            guard let id = ClaudeStepID(rawValue: stepID) else { return false }
            return prevClaudeStep(from: id) != nil
        case .cursor:
            let path = resolvedCursorPath()
            guard let id = CursorStepID(rawValue: stepID),
                  let i = path.firstIndex(of: id) else { return false }
            return i > 0
        case .chatgpt:
            guard let id = ChatGPTStepID(rawValue: stepID),
                  let i = ChatGPTStepID.allCases.firstIndex(of: id) else { return false }
            return i > 0
        case .manual:
            let path = resolvedManualPath()
            guard let id = ManualStepID(rawValue: stepID),
                  let i = path.firstIndex(of: id) else { return false }
            return i > 0
        }
    }

    private func goBack(for client: ConnectWizardClient) {
        statusMessage = nil
        switch client {
        case .claude:
            guard let id = ClaudeStepID(rawValue: stepID),
                  let prev = prevClaudeStep(from: id) else { return }
            stepID = prev.rawValue
        case .cursor:
            let path = resolvedCursorPath()
            guard let id = CursorStepID(rawValue: stepID),
                  let i = path.firstIndex(of: id), i > 0 else { return }
            stepID = path[i - 1].rawValue
        case .chatgpt:
            guard let id = ChatGPTStepID(rawValue: stepID),
                  let i = ChatGPTStepID.allCases.firstIndex(of: id), i > 0 else { return }
            stepID = ChatGPTStepID.allCases[i - 1].rawValue
        case .manual:
            let path = resolvedManualPath()
            guard let id = ManualStepID(rawValue: stepID),
                  let i = path.firstIndex(of: id), i > 0 else { return }
            stepID = path[i - 1].rawValue
        }
        refreshState()
    }

    // MARK: - Claude steps

    private func claudeStep() -> WizardStep {
        let id = ClaudeStepID(rawValue: stepID) ?? .binary
        switch id {
        case .binary:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                title: "First, we need a small helper program",
                body: "Agent Canvas talks to Claude through a helper file on your Mac. "
                    + "If it’s missing, build it once in Terminal, then come back here.",
                bullets: mcpExists
                    ? ["Helper found at \(shortPath(mcpPath))"]
                    : [
                        "Open Terminal",
                        "Run: cd ~/code/velox/agent-canvas && just build-rust",
                        "Return here and tap Recheck",
                    ],
                primary: WizardAction(
                    title: mcpExists ? "Continue" : "Recheck",
                    handler: {
                        refreshState()
                        if mcpExists {
                            stepID = resolvedClaudePath().first?.rawValue ?? ClaudeStepID.write.rawValue
                            note("Ready to continue", .good)
                        } else {
                            note("Still not found at \(shortPath(mcpPath))", .warn)
                        }
                    }
                ),
                secondary: WizardAction(title: "Copy helper path", handler: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mcpPath, forType: .string)
                    note("Path copied", .neutral)
                })
            )
        case .install:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                title: "Install Claude Desktop",
                body: "We couldn’t find Claude Desktop on this Mac. Install it from Anthropic, open it once, then quit it completely before continuing.",
                bullets: [
                    "Install Claude Desktop from claude.ai/download",
                    "Open it once so it creates its settings folder",
                    "Quit fully (Claude menu → Quit Claude)",
                ],
                primary: WizardAction(title: "Open download page", handler: {
                    if let url = URL(string: "https://claude.ai/download") {
                        NSWorkspace.shared.open(url)
                    }
                }),
                secondary: WizardAction(title: "I installed it — continue", handler: {
                    refreshState()
                    if claudeInstalled {
                        stepID = resolvedClaudePath().first(where: { $0 != .binary && $0 != .install })?
                            .rawValue ?? ClaudeStepID.write.rawValue
                        note("Claude Desktop found", .good)
                    } else {
                        note("Still not found — install Claude Desktop first", .warn)
                    }
                })
            )
        case .quit:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                title: claudeRunning ? "Quit Claude completely" : "Claude is quit — good",
                body: claudeRunning
                    ? "If Claude is open (even just the menu bar icon), it can overwrite our changes and remove Agent Canvas. "
                        + "Use Claude → Quit Claude — closing the window is not enough."
                    : "Claude is not running. You can continue and we’ll add Agent Canvas to its settings.",
                bullets: claudeRunning
                    ? [
                        "Click “Ask Claude to quit” below",
                        "Or use Claude menu → Quit Claude",
                        "Confirm Claude is gone from the menu bar and Dock",
                    ]
                    : nil,
                primary: WizardAction(
                    title: claudeRunning ? "Ask Claude to quit" : "Continue",
                    handler: {
                        if claudeRunning {
                            MCPClientInstall.requestClaudeQuit()
                            note("Asked Claude to quit…", .neutral)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                refreshState()
                                if !claudeRunning {
                                    note("Claude is quit", .good)
                                    stepID = nextClaudeStep(from: .quit)?.rawValue ?? ClaudeStepID.write.rawValue
                                } else {
                                    note("Still running — quit from the Claude menu, then tap Recheck", .warn)
                                }
                            }
                        } else {
                            stepID = nextClaudeStep(from: .quit)?.rawValue ?? ClaudeStepID.write.rawValue
                        }
                    }
                ),
                secondary: WizardAction(
                    title: claudeRunning ? "Recheck" : "I’m sure it’s quit",
                    handler: {
                        refreshState()
                        if claudeRunning {
                            note("Claude is still running", .warn)
                        } else {
                            stepID = nextClaudeStep(from: .quit)?.rawValue ?? ClaudeStepID.write.rawValue
                            note("Claude is quit", .good)
                        }
                    }
                )
            )
        case .write:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                title: "Add Agent Canvas to Claude",
                body: "We’ll update Claude’s settings file. Your other Claude preferences stay intact. "
                    + "Claude must stay quit while we do this.",
                bullets: [
                    "Writes to Claude’s Application Support folder",
                    "Does not use Claude “Plugins” — tools show under Connectors later",
                ],
                primary: WizardAction(
                    title: claudeRegistered ? "Already added — continue" : "Add to Claude",
                    disabled: !mcpExists,
                    handler: {
                        if claudeRegistered && !claudeRunning {
                            stepID = nextClaudeStep(from: .write)?.rawValue ?? ClaudeStepID.open.rawValue
                            return
                        }
                        runClaudeInstall()
                    }
                ),
                secondary: WizardAction(title: "Recheck settings file", handler: {
                    refreshState()
                    note(MCPClientInstall.claudeRegistrationSummary(), claudeRegistered ? .good : .warn)
                })
            )
        case .open:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                title: "Open Claude and find your tools",
                body: "Start Claude fresh (we already wrote the settings). Then connect the tools in a chat.",
                bullets: [
                    "Open Claude Desktop",
                    "In a new chat, click + → Connectors (not Plugins)",
                    "Look for agent-canvas / its tools",
                    "Optional: Settings → Developer for connection status",
                    "Keep Agent Canvas running in the menu bar",
                ],
                primary: WizardAction(title: "Open Claude Desktop", handler: {
                    MCPClientInstall.openClaudeDesktopApp()
                    note("Opened Claude — use + → Connectors", .neutral)
                }),
                secondary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied — paste into Claude after tools appear", .good)
                }),
                tertiary: WizardAction(title: "Continue", handler: {
                    stepID = ClaudeStepID.done.rawValue
                })
            )
        case .done:
            let already = claudeRegistered && mcpExists
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                heroSymbol: "checkmark.seal.fill",
                title: already ? "Already connected" : "Try it out",
                body: already
                    ? "Agent Canvas is already set up for Claude. You can copy a starter message, or run setup again if something broke."
                    : "Add an Agent Canvas widget to your desktop if you haven’t, then ask Claude to update a canvas by name (for example sm-one or md-one).",
                bullets: [
                    "Desktop → right-click → Edit Widgets → search Agent Canvas",
                    "Leave Agent Canvas in the menu bar so widgets stay live",
                ],
                primary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied", .good)
                }),
                secondary: WizardAction(
                    title: already ? "Run setup again" : "How to add widgets",
                    handler: {
                        if already {
                            // Force full path including quit/write so user can repair.
                            stepID = ClaudeStepID.quit.rawValue
                            if !claudeRunning {
                                stepID = ClaudeStepID.write.rawValue
                            }
                            note(nil)
                            statusMessage = nil
                            refreshState()
                        } else {
                            note("Desktop → right-click → Edit Widgets → search Agent Canvas", .neutral)
                        }
                    }
                ),
                isTerminal: true
            )
        }
    }

    // MARK: - Cursor steps

    private func cursorStep() -> WizardStep {
        let id = CursorStepID(rawValue: stepID) ?? .binary
        switch id {
        case .binary:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Cursor",
                heroSubtitle: "Connect Agent Canvas so Cursor can update your widgets.",
                title: "First, we need a small helper program",
                body: "Cursor starts this helper when you chat. If it’s missing, build it once, then continue.",
                bullets: mcpExists
                    ? ["Helper found at \(shortPath(mcpPath))"]
                    : [
                        "Open Terminal",
                        "Run: cd ~/code/velox/agent-canvas && just build-rust",
                        "Return here and tap Recheck",
                    ],
                primary: WizardAction(
                    title: mcpExists ? "Continue" : "Recheck",
                    handler: {
                        refreshState()
                        if mcpExists {
                            stepID = CursorStepID.install.rawValue
                            note("Ready to continue", .good)
                        } else {
                            note("Still not found at \(shortPath(mcpPath))", .warn)
                        }
                    }
                )
            )
        case .install:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Cursor",
                heroSubtitle: cursorInstalled
                    ? "One click opens Cursor’s install dialog."
                    : "Install Cursor if needed, then register Agent Canvas.",
                title: "Add Agent Canvas to Cursor",
                body: "The easiest path opens Cursor’s install dialog. You’ll confirm once. "
                    + "If that doesn’t work, we can write Cursor’s config file directly.",
                bullets: [
                    "Confirm “agent-canvas” if Cursor asks",
                    "Keep Agent Canvas running in the menu bar afterward",
                ],
                primary: WizardAction(
                    title: "Open Cursor install…",
                    disabled: !mcpExists,
                    handler: { runCursorInstall() }
                ),
                secondary: WizardAction(
                    title: "Write config file instead",
                    disabled: !mcpExists,
                    handler: { runCursorFileFallback() }
                ),
                tertiary: !cursorInstalled
                    ? WizardAction(title: "Get Cursor", handler: {
                        if let url = URL(string: "https://cursor.com") {
                            NSWorkspace.shared.open(url)
                        }
                    })
                    : nil
            )
        case .confirm:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Cursor",
                heroSubtitle: "Make sure Cursor loaded Agent Canvas.",
                title: "Confirm in Cursor",
                body: "If Cursor showed an install dialog, accept it. Then reload the window or restart Cursor if tools don’t appear.",
                bullets: [
                    "Look for agent-canvas under Cursor MCP / tools",
                    "Reload the window if tools are missing",
                ],
                primary: WizardAction(title: "Recheck connection", handler: {
                    refreshState()
                    if cursorRegistered {
                        note("Found in Cursor’s config", .good)
                        stepID = CursorStepID.done.rawValue
                    } else {
                        note("Not listed yet — run install again or write the config file", .warn)
                    }
                }),
                secondary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied", .good)
                }),
                tertiary: WizardAction(title: "Continue anyway", handler: {
                    stepID = CursorStepID.done.rawValue
                })
            )
        case .done:
            let already = cursorRegistered && mcpExists
            return WizardStep(
                id: id.rawValue,
                heroTitle: "",
                heroSubtitle: "",
                heroSymbol: "checkmark.seal.fill",
                title: already ? "Already connected" : "Try it out",
                body: already
                    ? "Agent Canvas is already set up for Cursor. You can copy a starter message, or run setup again if tools disappeared."
                    : "Add a widget if you haven’t, then paste a starter message into Cursor.",
                bullets: [
                    "Desktop → Edit Widgets → Agent Canvas",
                    "Ask Cursor to update a canvas id like md-one",
                ],
                primary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied", .good)
                }),
                secondary: already
                    ? WizardAction(title: "Run setup again", handler: {
                        stepID = CursorStepID.install.rawValue
                        statusMessage = nil
                        refreshState()
                    })
                    : nil,
                isTerminal: true
            )
        }
    }

    // MARK: - ChatGPT steps

    private func chatgptStep() -> WizardStep {
        let id = ChatGPTStepID(rawValue: stepID) ?? .explain
        switch id {
        case .explain:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "ChatGPT",
                heroSubtitle: "Local desktop agents aren’t supported in ChatGPT yet.",
                title: "ChatGPT can’t use this local helper",
                body: "ChatGPT expects online connectors (a web address), not a program on your Mac. "
                    + "Agent Canvas today works with apps that run a local MCP helper — Cursor and Claude Desktop.",
                primary: WizardAction(title: "See my options", handler: {
                    stepID = ChatGPTStepID.options.rawValue
                })
            )
        case .options:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "ChatGPT",
                heroSubtitle: "Pick how you want to continue.",
                title: "What you can do",
                body: "For the full experience, use Cursor or Claude Desktop. "
                    + "You can also copy a config for another local app that supports MCP.",
                primary: WizardAction(title: "Set up Cursor instead", handler: {
                    activeClient = .cursor
                    reloadWatcher.preferredConnectClient = .cursor
                    enterFirstStep()
                }),
                secondary: WizardAction(title: "Set up Claude Desktop instead", handler: {
                    activeClient = .claude
                    reloadWatcher.preferredConnectClient = .claude
                    enterFirstStep()
                }),
                tertiary: WizardAction(title: "Copy config for another app", handler: {
                    copyConfig()
                    stepID = ChatGPTStepID.done.rawValue
                })
            )
        case .done:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Next steps",
                heroSubtitle: "When ChatGPT supports local helpers, we’ll add a direct path.",
                heroSymbol: "clock.fill",
                title: "You’re all set for now",
                body: "Finish setup with Cursor or Claude when you’re ready. Keep Agent Canvas in the menu bar so widgets update live.",
                primary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied (use in Cursor or Claude)", .good)
                }),
                isTerminal: true
            )
        }
    }

    // MARK: - Manual steps

    private func manualStep() -> WizardStep {
        let id = ManualStepID(rawValue: stepID) ?? .binary
        switch id {
        case .binary:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Other app",
                heroSubtitle: "We’ll give you a config snippet your app can paste.",
                title: "First, we need a small helper program",
                body: "Most MCP apps start a local helper. Build it if needed, then continue.",
                bullets: mcpExists
                    ? ["Helper found at \(shortPath(mcpPath))"]
                    : ["Run: cd ~/code/velox/agent-canvas && just build-rust"],
                primary: WizardAction(
                    title: mcpExists ? "Continue" : "Recheck",
                    handler: {
                        refreshState()
                        if mcpExists {
                            stepID = ManualStepID.copy.rawValue
                        } else {
                            note("Still not found", .warn)
                        }
                    }
                )
            )
        case .copy:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Other app",
                heroSubtitle: "Copy the MCP server block to your clipboard.",
                title: "Copy the setup snippet",
                body: "This JSON tells your app how to start Agent Canvas. Paste it where that app asks for MCP servers.",
                primary: WizardAction(title: "Copy setup snippet", handler: {
                    copyConfig()
                    stepID = ManualStepID.paste.rawValue
                })
            )
        case .paste:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "Other app",
                heroSubtitle: "Paste into your client’s MCP settings.",
                title: "Paste into your app",
                body: "Open your app’s MCP or developer settings and add a server. "
                    + "Helper path: \(shortPath(mcpPath))",
                bullets: [
                    "Cursor: Settings → MCP, or ~/.cursor/mcp.json",
                    "Claude: Developer → Edit Config (quit Claude first)",
                    "Others: follow that product’s “add MCP server” docs",
                ],
                primary: WizardAction(title: "Copy snippet again", handler: { copyConfig() }),
                secondary: WizardAction(title: "Continue", handler: {
                    stepID = ManualStepID.done.rawValue
                })
            )
        case .done:
            return WizardStep(
                id: id.rawValue,
                heroTitle: "You’re set",
                heroSubtitle: "Restart your app if tools don’t appear.",
                heroSymbol: "checkmark.seal.fill",
                title: "Finish up",
                body: "Keep Agent Canvas in the menu bar. Add desktop widgets, then ask your agent to update a canvas id.",
                primary: WizardAction(title: "Copy a starter message", handler: {
                    UserGuide.copyExamplePrompt()
                    note("Starter message copied", .good)
                }),
                isTerminal: true
            )
        }
    }

    // MARK: - Actions

    private func refreshState() {
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        mcpPath = resolved.path
        mcpExists = resolved.exists
        cursorRegistered = MCPClientInstall.isRegisteredInCursor()
        claudeRegistered = MCPClientInstall.isRegisteredInClaude()
        claudeRunning = MCPClientInstall.isClaudeRunning()
        cursorInstalled = MCPClientInstall.isCursorInstalled()
        claudeInstalled = MCPClientInstall.isClaudeDesktopInstalled()
    }

    private func startPollingIfNeeded() {
        pollTimer?.invalidate()
        pollTimer = nil
        // Poll while on Claude quit/write so chips stay live.
        guard activeClient == .claude,
              stepID == ClaudeStepID.quit.rawValue || stepID == ClaudeStepID.write.rawValue
        else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let wasRunning = claudeRunning
                refreshState()
                if wasRunning && !claudeRunning && stepID == ClaudeStepID.quit.rawValue {
                    note("Claude is quit", .good)
                }
            }
        }
    }

    private func runCursorInstall() {
        refreshState()
        guard mcpExists else {
            note("Helper missing — run just build-rust", .warn)
            return
        }
        let result = MCPClientInstall.connectCursor(command: mcpPath)
        note(result.message, result.ok ? .good : .warn)
        reloadWatcher.statusLine = result.message
        refreshState()
        if result.ok {
            stepID = CursorStepID.confirm.rawValue
        }
    }

    private func runCursorFileFallback() {
        refreshState()
        guard mcpExists else {
            note("Helper missing — run just build-rust", .warn)
            return
        }
        let result = MCPClientInstall.installToCursorConfig(command: mcpPath)
        note(result.message, result.ok ? .good : .warn)
        reloadWatcher.statusLine = result.message
        refreshState()
        if result.ok {
            stepID = CursorStepID.confirm.rawValue
        }
    }

    private func runClaudeInstall() {
        refreshState()
        guard mcpExists else {
            note("Helper missing — run just build-rust", .warn)
            return
        }
        if claudeRunning {
            note("Claude is still running — quit completely first", .warn)
            stepID = ClaudeStepID.quit.rawValue
            return
        }
        let result = MCPClientInstall.connectClaudeDesktop(command: mcpPath)
        note(result.message, result.ok ? .good : .bad)
        reloadWatcher.setStatusLine(result.message)
        refreshState()
        if result.ok {
            stepID = nextClaudeStep(from: .write)?.rawValue ?? ClaudeStepID.open.rawValue
        }
    }

    private func copyConfig() {
        refreshState()
        let json = MCPClientInstall.prettyJSON(MCPClientInstall.mcpServersBlock(command: mcpPath))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        note(
            mcpExists ? "Setup snippet copied" : "Snippet copied — fix the helper path after building",
            mcpExists ? .good : .warn
        )
        reloadWatcher.statusLine = statusMessage ?? ""
    }

    private func note(_ message: String?, _ tone: StatusTone = .neutral) {
        statusMessage = message
        statusTone = tone
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Client presentation

private extension ConnectWizardClient {
    var symbolName: String {
        switch self {
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "bubble.left.and.bubble.right.fill"
        case .chatgpt: return "sparkles"
        case .manual: return "doc.text.fill"
        }
    }

    var accent: Color {
        switch self {
        case .cursor: return Color(red: 0.35, green: 0.55, blue: 1.0)
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .chatgpt: return Color(red: 0.35, green: 0.75, blue: 0.55)
        case .manual: return Color.secondary
        }
    }

    /// Window title: “Connect from Claude”, etc.
    var windowTitleName: String {
        switch self {
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .manual: return "your app"
        }
    }
}
