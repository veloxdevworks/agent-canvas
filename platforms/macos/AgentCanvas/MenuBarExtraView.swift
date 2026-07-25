import SwiftUI
import AppKit

/// Native menu bar menu (`.menu` style) with real side submenus.
///
/// End users get **actions**, not a status dashboard. Technical health is assumed
/// OK while the host is running; we only surface a line when something is wrong
/// (e.g. MCP binary missing).
///
/// **Important:** Do **not** observe `ReloadWatcher` via `@EnvironmentObject`.
/// Any publish rebuilds the NSMenu and dismisses open submenus mid-hover.
struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var problemLine: String?

    var body: some View {
        Group {
            // Only when unhealthy — otherwise silence is correct UX.
            if let problemLine {
                Text(problemLine)
                Divider()
            }

            Button("Open Agent Canvas…") {
                openWindow(id: "main")
                activateApp()
            }

            Button("How to Use…") {
                openWindow(id: "main")
                activateApp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .agentCanvasShowHowTo, object: nil)
                }
            }

            Menu("Connect MCP") {
                Button("Cursor…") {
                    openConnectWizard(.cursor)
                }
                Button("Claude Desktop…") {
                    openConnectWizard(.claude)
                }
                Button("ChatGPT…") {
                    openConnectWizard(.chatgpt)
                }
                Divider()
                Button("Other / manual config…") {
                    openConnectWizard(.manual)
                }
                Divider()
                Button("Copy MCP Config") {
                    copyMCPConfig()
                }
            }

            Divider()

            Button("Send Feedback…") {
                UserGuide.openSendFeedback()
            }
            Button("Report Issue…") {
                UserGuide.openReportIssue()
            }

            Divider()

            Button("Quit Agent Canvas") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            // Watcher is started by AppDelegate; ensure HostRuntime link is warm.
            HostRuntime.watcher?.start()
            problemLine = Self.currentProblemLine()
        }
    }

    /// Non-nil only when the user should act (not “everything is fine” telemetry).
    private static func currentProblemLine() -> String? {
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        if !resolved.exists {
            return "MCP binary missing — connect may fail until it’s installed"
        }
        return nil
    }

    // MARK: - Actions

    private func openConnectWizard(_ client: ConnectWizardClient) {
        let path = AgentCanvasPaths.mcpBinaryResolved()
        if let w = HostRuntime.watcher {
            w.preferredConnectClient = client
            if !path.exists && client != .chatgpt {
                w.setStatusLine(
                    "MCP binary not found — run just build-rust, then open Connect again"
                )
            }
        }
        openWindow(id: "connect-wizard")
        activateApp()
    }

    private func activateApp() {
        // Bring windows forward while remaining a menu-bar agent.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copyMCPConfig() {
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        let json = MCPClientInstall.prettyJSON(
            MCPClientInstall.mcpServersBlock(command: resolved.path)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        HostRuntime.watcher?.setStatusLine(
            resolved.exists
                ? "MCP config copied"
                : "Config copied, but binary missing — fix command path after just build-rust"
        )
    }
}
