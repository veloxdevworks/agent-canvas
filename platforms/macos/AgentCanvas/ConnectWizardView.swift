import SwiftUI
import AppKit

/// Guided setup for MCP clients — full wizard for non–one-click paths;
/// short confirm flow for Cursor.
struct ConnectWizardView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.dismiss) private var dismiss

    @State private var client: ConnectWizardClient
    @State private var stepIndex = 0
    @State private var mcpPath = AgentCanvasPaths.preferredMCPBinaryPath()
    @State private var mcpExists = false
    @State private var lastActionMessage: String?
    @State private var cursorRegistered = false
    @State private var claudeRegistered = false

    init(client: ConnectWizardClient = .cursor) {
        _client = State(initialValue: client)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    clientPicker
                    stepContent
                    if let lastActionMessage {
                        Text(lastActionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            client = reloadWatcher.preferredConnectClient
            stepIndex = 0
            refresh()
        }
        .onChange(of: reloadWatcher.preferredConnectClient) { _, newValue in
            client = newValue
            stepIndex = 0
            lastActionMessage = nil
            refresh()
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your agent")
                    .font(.title2.bold())
                Text(client.title)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Step \(stepIndex + 1) of \(steps.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private var clientPicker: some View {
        Picker("Client", selection: $client) {
            ForEach(ConnectWizardClient.allCases) { c in
                Text(c.title).tag(c)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: client) { _, _ in
            stepIndex = 0
            lastActionMessage = nil
            refresh()
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
            Spacer()
            if stepIndex > 0 {
                Button("Back") { stepIndex -= 1 }
            }
            if stepIndex < steps.count - 1 {
                Button("Next") { stepIndex += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") {
                    UserGuide.hasCompletedOnboarding = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    // MARK: - Steps

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let body: String
        var primaryAction: String?
        var action: (() -> Void)?
        var secondaryAction: String?
        var secondary: (() -> Void)?
    }

    private var steps: [Step] {
        switch client {
        case .cursor: return cursorSteps
        case .claude: return claudeSteps
        case .chatgpt: return chatgptSteps
        case .manual: return manualSteps
        }
    }

    private var stepContent: some View {
        let step = steps[min(stepIndex, steps.count - 1)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(step.title)
                .font(.headline)
            Text(step.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !mcpExists {
                Label(
                    "MCP binary not found at \(shortPath(mcpPath)). Run just build-rust (or install agent-canvas-mcp), then continue.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if let primary = step.primaryAction, let action = step.action {
                    Button(primary, action: action)
                        .buttonStyle(.borderedProminent)
                        .disabled(needsBinary(for: primary) && !mcpExists)
                }
                if let secondary = step.secondaryAction, let action = step.secondary {
                    Button(secondary, action: action)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)

            if client == .cursor && cursorRegistered {
                Label("Cursor config already includes agent-canvas", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            if client == .claude {
                if claudeRegistered {
                    Label(
                        MCPClientInstall.claudeRegistrationSummary(),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .font(.caption)
                } else {
                    Label(
                        MCPClientInstall.claudeRegistrationSummary(),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
                if MCPClientInstall.isClaudeRunning() {
                    Label("Claude is running — quit before writing config", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func needsBinary(for title: String) -> Bool {
        title.localizedCaseInsensitiveContains("install")
            || title.localizedCaseInsensitiveContains("write")
            || title.localizedCaseInsensitiveContains("open cursor")
            || title.localizedCaseInsensitiveContains("add to")
    }

    // MARK: - Per-client steps

    private var cursorSteps: [Step] {
        [
            Step(
                id: 0,
                title: "One-click install in Cursor",
                body: "Cursor can register Agent Canvas via an install dialog. "
                    + "You’ll confirm once in Cursor. Keep this app running afterward so widgets reload when the agent writes.",
                primaryAction: "Open Cursor install…",
                action: { runCursorInstall() },
                secondaryAction: "Write ~/.cursor/mcp.json instead",
                secondary: { runCursorFileFallback() }
            ),
            Step(
                id: 1,
                title: "Confirm in Cursor",
                body: "In Cursor’s dialog, install “agent-canvas”. "
                    + "If tools don’t appear, reload the window or restart Cursor. "
                    + "Then try the example prompt.",
                primaryAction: "Copy example prompt",
                action: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied — paste into a Cursor chat"
                },
                secondaryAction: "Recheck connection",
                secondary: {
                    refresh()
                    lastActionMessage = cursorRegistered
                        ? "agent-canvas is in Cursor’s MCP config"
                        : "Not in config yet — run install again or write mcp.json"
                }
            ),
            Step(
                id: 2,
                title: "Use it",
                body: "Ask Cursor to update a canvas by id (e.g. md-one). "
                    + "Add widgets from the desktop: Edit Widgets → Agent Canvas. "
                    + "Menu bar stays running for live reloads.",
                primaryAction: "Copy example prompt",
                action: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied"
                },
                secondaryAction: "How to add widgets",
                secondary: {
                    lastActionMessage =
                        "Desktop → right-click → Edit Widgets → search Agent Canvas"
                }
            ),
        ]
    }

    private var claudeSteps: [Step] {
        [
            Step(
                id: 0,
                title: "Quit Claude Desktop first",
                body: "Claude rewrites its config when it runs and can wipe mcpServers. "
                    + "Fully quit before we write (Claude menu → Quit Claude — not just close the window). "
                    + "Confirm the Claude icon is gone from the menu bar / Dock.",
                primaryAction: "Request Claude quit",
                action: {
                    MCPClientInstall.requestClaudeQuit()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        refresh()
                        lastActionMessage = MCPClientInstall.isClaudeRunning()
                            ? "Claude still running — use Claude → Quit Claude manually"
                            : "Claude is not running — continue to write config"
                        if !MCPClientInstall.isClaudeRunning() {
                            stepIndex = min(stepIndex + 1, steps.count - 1)
                        }
                    }
                },
                secondaryAction: "I’m sure it’s quit — next",
                secondary: {
                    if MCPClientInstall.isClaudeRunning() {
                        lastActionMessage = "Claude still appears to be running"
                    } else {
                        stepIndex = min(stepIndex + 1, steps.count - 1)
                    }
                }
            ),
            Step(
                id: 1,
                title: "Write Claude Desktop config",
                body: "We’ll merge agent-canvas into "
                    + "~/Library/Application Support/Claude/claude_desktop_config.json "
                    + "without removing Claude’s other preferences. "
                    + "Local MCP is not a “Plugin” — look under Connectors after restart.",
                primaryAction: "Add to Claude config",
                action: { runClaudeInstall() },
                secondaryAction: "Recheck config file",
                secondary: {
                    refresh()
                    lastActionMessage = MCPClientInstall.claudeRegistrationSummary()
                }
            ),
            Step(
                id: 2,
                title: "Open Claude & find tools",
                body: "1. Open Claude Desktop (fresh start).\n"
                    + "2. In a chat, click + → Connectors (not Plugins/Extensions).\n"
                    + "3. You should see agent-canvas / its tools.\n"
                    + "4. Also: Settings → Developer for MCP connection status & logs.\n"
                    + "5. Keep Agent Canvas running in the menu bar for widget reloads.",
                primaryAction: "Open Claude Desktop",
                action: {
                    MCPClientInstall.openClaudeDesktopApp()
                    lastActionMessage = "Opened Claude — check + → Connectors"
                },
                secondaryAction: "Copy example prompt",
                secondary: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied — paste into Claude after tools show"
                }
            ),
        ]
    }

    private var chatgptSteps: [Step] {
        [
            Step(
                id: 0,
                title: "ChatGPT doesn’t support local stdio MCP",
                body: "ChatGPT expects remote connectors / developer plugins (a URL), not a local binary. "
                    + "Agent Canvas today is a local stdio MCP server spawned by Cursor or Claude Desktop. "
                    + "For the best experience, use one of those.",
                primaryAction: "Switch to Cursor setup",
                action: {
                    client = .cursor
                    stepIndex = 0
                },
                secondaryAction: "Switch to Claude setup",
                secondary: {
                    client = .claude
                    stepIndex = 0
                }
            ),
            Step(
                id: 1,
                title: "What you can do today",
                body: "• Use Cursor or Claude Desktop with Connect MCP (recommended).\n"
                    + "• Copy the MCP config for other local clients that support stdio.\n"
                    + "• Later we may add an HTTP MCP for ChatGPT connectors — not available yet.",
                primaryAction: "Copy MCP config",
                action: {
                    copyConfig()
                    lastActionMessage = "Config copied for stdio-capable clients"
                },
                secondaryAction: "Copy example prompt",
                secondary: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied (use in Cursor/Claude)"
                }
            ),
            Step(
                id: 2,
                title: "Still want ChatGPT later?",
                body: "When HTTP MCP ships, you’ll start a local server and paste a URL into "
                    + "ChatGPT Settings → Connectors / Developer mode. "
                    + "For now, finish setup with Cursor or Claude, add widgets, and keep this app in the menu bar.",
                primaryAction: "Copy example prompt",
                action: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied"
                }
            ),
        ]
    }

    private var manualSteps: [Step] {
        [
            Step(
                id: 0,
                title: "Copy the MCP server config",
                body: "Most MCP clients use an mcpServers JSON block. "
                    + "We’ll put agent-canvas on the clipboard with the path to your local binary.",
                primaryAction: "Copy MCP config",
                action: { copyConfig() }
            ),
            Step(
                id: 1,
                title: "Paste into your client",
                body: "Examples:\n"
                    + "• Cursor: Settings → MCP, or ~/.cursor/mcp.json\n"
                    + "• Claude Desktop: Developer → Edit Config\n"
                    + "• Other: follow that product’s “add MCP server” docs\n\n"
                    + "Command path: \(mcpPath)",
                primaryAction: "Copy MCP config again",
                action: { copyConfig() },
                secondaryAction: "Open Claude config folder",
                secondary: {
                    let dir = MCPClientInstall.claudeConfigURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                    lastActionMessage = "Opened Claude Application Support folder"
                }
            ),
            Step(
                id: 2,
                title: "Use Agent Canvas",
                body: "Restart the client if needed. Keep Agent Canvas in the menu bar. "
                    + "Add widgets from Edit Widgets, then ask the agent to update md-one (or another id).",
                primaryAction: "Copy example prompt",
                action: {
                    UserGuide.copyExamplePrompt()
                    lastActionMessage = "Example prompt copied"
                }
            ),
        ]
    }

    // MARK: - Actions

    private func refresh() {
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        mcpPath = resolved.path
        mcpExists = resolved.exists
        cursorRegistered = MCPClientInstall.isRegisteredInCursor()
        claudeRegistered = MCPClientInstall.isRegisteredInClaude()
    }

    private func runCursorInstall() {
        refresh()
        guard mcpExists else {
            lastActionMessage = "MCP binary missing — run just build-rust"
            reloadWatcher.statusLine = lastActionMessage ?? ""
            return
        }
        let result = MCPClientInstall.connectCursor(command: mcpPath)
        lastActionMessage = result.message
        reloadWatcher.statusLine = result.message
        refresh()
        if result.ok { stepIndex = min(stepIndex + 1, steps.count - 1) }
    }

    private func runCursorFileFallback() {
        refresh()
        guard mcpExists else {
            lastActionMessage = "MCP binary missing — run just build-rust"
            return
        }
        let result = MCPClientInstall.installToCursorConfig(command: mcpPath)
        lastActionMessage = result.message
        reloadWatcher.statusLine = result.message
        refresh()
    }

    private func runClaudeInstall() {
        refresh()
        guard mcpExists else {
            lastActionMessage = "MCP binary missing — run just build-rust"
            reloadWatcher.setStatusLine(lastActionMessage ?? "")
            return
        }
        if MCPClientInstall.isClaudeRunning() {
            lastActionMessage =
                "Claude is still running — quit it first so it doesn’t wipe mcpServers"
            return
        }
        let result = MCPClientInstall.connectClaudeDesktop(command: mcpPath)
        lastActionMessage = result.message
        reloadWatcher.setStatusLine(result.message)
        refresh()
        if result.ok { stepIndex = min(stepIndex + 1, steps.count - 1) }
    }

    private func copyConfig() {
        refresh()
        let json = MCPClientInstall.prettyJSON(MCPClientInstall.mcpServersBlock(command: mcpPath))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        lastActionMessage = mcpExists
            ? "MCP config copied"
            : "Config copied — fix command path after building the binary"
        reloadWatcher.statusLine = lastActionMessage ?? ""
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
