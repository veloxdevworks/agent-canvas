import Foundation
import AppKit

/// Shared onboarding copy, prefs, and clipboard helpers for end-user flows.
enum UserGuide {
    private static let completedKey = "agentcanvas.onboarding.completed"
    private static let checklistDismissedKey = "agentcanvas.checklist.dismissed"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static var checklistDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: checklistDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: checklistDismissedKey) }
    }

    static func resetOnboardingFlags() {
        hasCompletedOnboarding = false
        checklistDismissed = false
    }

    /// Paste into Cursor / Claude after MCP is connected.
    static let examplePrompt = """
    Update Agent Canvas canvas `md-one` with:
    - a short header titled “Sprint pulse”
    - 3 metrics (e.g. closed, cycle time, WIP)
    - a small bar chart for the last 5 weekdays
    Keep it glanceable — this is a medium widget, not a document.
    """

    static let steps: [(title: String, body: String)] = [
        (
            "Add widgets",
            "Right-click the desktop → Edit Widgets → search “Agent Canvas”. "
                + "Add sizes you want (e.g. Medium · One). Each widget has a fixed id like md-one."
        ),
        (
            "Connect your agent",
            "Menu bar → Connect MCP → Cursor or Claude Desktop. "
                + "ChatGPT does not support local MCP yet (Not available). "
                + "Canvas data stays on this Mac by default — see Privacy in the project docs."
        ),
        (
            "Ask the agent to update a canvas",
            "In Cursor or Claude, ask it to update a canvas by id (e.g. md-one). "
                + "Keep Agent Canvas running in the menu bar so widgets reload."
        ),
    ]

    /// Public privacy policy in the source repo (until a product site hosts a copy).
    static let privacyURL = URL(string: "https://github.com/veloxdevworks/agent-canvas/blob/main/PRIVACY.md")!

    static func openPrivacy() {
        NSWorkspace.shared.open(privacyURL)
    }

    static func copyExamplePrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(examplePrompt, forType: .string)
    }

    static func copyCanvasId(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    static func copyUpdatePrompt(for canvasId: String) {
        let prompt = """
        Update Agent Canvas canvas `\(canvasId)` with a short header and a few glanceable metrics. \
        Keep content dense enough for that widget size.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    /// Public inbox for product feedback and bug reports.
    static let feedbackEmail = "feedback@veloxdevworks.com"

    /// Full diagnostics blob for bug reports (also used by Report Issue).
    @MainActor
    static func diagnosticsText() -> String {
        let w = HostRuntime.watcher
        let base = w?.diagnosticsReport() ?? "Watcher not started"
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        return base
            + "\nmcpBinary: \(resolved.path)"
            + "\nmcpExists: \(resolved.exists)"
            + "\ncursorRegistered: \(MCPClientInstall.isRegisteredInCursor())"
            + "\nclaudeRegistered: \(MCPClientInstall.isRegisteredInClaude())"
    }

    @MainActor
    static func copyDiagnostics() {
        let text = diagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        HostRuntime.watcher?.setStatusLine("Diagnostics copied to clipboard")
    }

    /// Freeform product feedback — no template or diagnostics prefill.
    @MainActor
    static func openSendFeedback() {
        openMail(
            subject: "Agent Canvas feedback",
            body: "",
            attachments: []
        )
        HostRuntime.watcher?.setStatusLine("Feedback draft opened → \(feedbackEmail)")
    }

    /// Bug report: opens mail to the feedback alias with diagnostics as file attachment(s).
    @MainActor
    static func openReportIssue() {
        let diag = diagnosticsText()
        var attachments: [URL] = []

        if let url = writeTempAttachment(
            filename: "agent-canvas-diagnostics.txt",
            contents: diag
        ) {
            attachments.append(url)
        }

        // Recent MCP call log if present (helps explain failed tool attempts).
        let calls = CanvasStorage.applicationSupportRoot.appendingPathComponent("mcp-calls.jsonl")
        if FileManager.default.fileExists(atPath: calls.path) {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("agent-canvas-mcp-calls.jsonl")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: calls, to: dest)) != nil {
                attachments.append(dest)
            }
        }

        openMail(
            subject: "Agent Canvas issue (\(Bundle.main.shortVersion))",
            body: feedbackBody() + """

            ## Attachments
            Diagnostics are attached (agent-canvas-diagnostics.txt). \
            If present, mcp-calls.jsonl has recent tool call shapes/errors.

            """,
            attachments: attachments
        )
        HostRuntime.watcher?.setStatusLine(
            "Issue draft opened → \(feedbackEmail) (diagnostics attached)"
        )
    }

    @MainActor
    private static func feedbackBody() -> String {
        let w = HostRuntime.watcher
        let version = Bundle.main.shortVersion
        let build = Bundle.main.buildVersion
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let filled = w?.canvasFillSummary ?? "?"
        let resolved = AgentCanvasPaths.mcpBinaryResolved()
        return """
        ## What happened?


        ## Environment
        - Agent Canvas \(version) (\(build))
        - macOS \(os)
        - Canvases: \(filled)
        - MCP: \(resolved.path) (exists=\(resolved.exists))
        - Cursor connected: \(MCPClientInstall.isRegisteredInCursor())
        - Claude connected: \(MCPClientInstall.isRegisteredInClaude())
        - Last reload: \(w?.lastReload?.description ?? "never")

        """
    }

    private static func writeTempAttachment(filename: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Prefer Mail compose with real attachments; fall back to mailto (body only).
    private static func openMail(subject: String, body: String, attachments: [URL]) {
        if !attachments.isEmpty,
           let service = NSSharingService(named: .composeEmail),
           service.canPerform(withItems: attachments)
        {
            service.recipients = [feedbackEmail]
            service.subject = subject
            var items: [Any] = [body]
            items.append(contentsOf: attachments)
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
            // Some clients accept attachments without body as a separate item shape.
            service.perform(withItems: attachments)
            // Body may be empty — put body on clipboard as backup.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            return
        }

        // mailto cannot attach files; put diagnostics on clipboard if we had any.
        if !attachments.isEmpty, let first = attachments.first,
           let text = try? String(contentsOf: first, encoding: .utf8)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = feedbackEmail
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(
                name: "body",
                value: body + (attachments.isEmpty
                    ? ""
                    : "\n\n(Diagnostics could not be attached automatically — pasted to clipboard.)\n")
            ),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Which connect wizard path to open.
enum ConnectWizardClient: String, Identifiable, CaseIterable {
    case cursor
    case claude
    case chatgpt
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .claude: return "Claude Desktop"
        case .chatgpt: return "ChatGPT"
        case .manual: return "Other / manual config"
        }
    }

    /// True when we can mostly automate (still may need a confirm dialog).
    var isOneClick: Bool {
        switch self {
        case .cursor: return true
        case .claude, .chatgpt, .manual: return false
        }
    }
}
