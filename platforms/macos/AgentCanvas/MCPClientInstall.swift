import Foundation
import AppKit

/// One-click / one-file MCP registration for agent hosts we can reach from the host app.
///
/// - **Cursor:** official deeplink (`cursor://…/mcp/install`) + optional `~/.cursor/mcp.json` merge.
/// - **Claude Desktop:** merge into `claude_desktop_config.json` (user restarts Claude).
/// - **ChatGPT:** no local stdio install path yet — show guidance only.
enum MCPClientInstall {
    static let serverName = "agent-canvas"

    // MARK: - Public API

    struct Result: Equatable {
        var ok: Bool
        var message: String
    }

    /// JSON object for one server entry: `{ "command", "args" }` (Cursor deeplink / snippet).
    static func serverConfig(command: String) -> [String: Any] {
        [
            "command": command,
            "args": ["stdio"],
        ]
    }

    /// Full `mcpServers` block for paste / Claude / Cursor files.
    static func mcpServersBlock(command: String) -> [String: Any] {
        [
            "mcpServers": [
                serverName: serverConfig(command: command),
            ],
        ]
    }

    static func prettyJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return str
            .replacingOccurrences(of: "\\/", with: "/")
    }

    // MARK: - Cursor

    /// `cursor://anysphere.cursor-deeplink/mcp/install?name=…&config=…`
    static func cursorInstallURL(command: String) -> URL? {
        let config = serverConfig(command: command)
        guard JSONSerialization.isValidJSONObject(config),
              let data = try? JSONSerialization.data(withJSONObject: config, options: [])
        else { return nil }
        let b64 = data.base64EncodedString()
        var comps = URLComponents()
        comps.scheme = "cursor"
        comps.host = "anysphere.cursor-deeplink"
        comps.path = "/mcp/install"
        comps.queryItems = [
            URLQueryItem(name: "name", value: serverName),
            URLQueryItem(name: "config", value: b64),
        ]
        return comps.url
    }

    static func isCursorInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
            || FileManager.default.fileExists(
                atPath: NSHomeDirectory() + "/Applications/Cursor.app"
            )
    }

    /// Open Cursor’s one-click install dialog. Falls back to writing `~/.cursor/mcp.json`.
    static func connectCursor(command: String) -> Result {
        if let url = cursorInstallURL(command: command),
           NSWorkspace.shared.open(url)
        {
            return Result(
                ok: true,
                message: "Opened Cursor install dialog — confirm “agent-canvas”, then restart if needed"
            )
        }
        // Deeplink failed (Cursor not registered) — merge global mcp.json.
        return installToCursorConfig(command: command)
    }

    static var cursorConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json")
    }

    static func installToCursorConfig(command: String) -> Result {
        mergeServerIntoJSONFile(
            url: cursorConfigURL,
            command: command,
            createParents: true
        ).mapMessage { base in
            "Wrote ~/.cursor/mcp.json — restart Cursor to load agent-canvas"
        }
    }

    static func isRegisteredInCursor(commandHint: String? = nil) -> Bool {
        isServerRegistered(in: cursorConfigURL)
    }

    // MARK: - Claude Desktop

    static var claudeConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    static func isClaudeDesktopInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
            || FileManager.default.fileExists(
                atPath: NSHomeDirectory() + "/Applications/Claude.app"
            )
    }

    /// Whether Claude Desktop appears to be running (including menu-bar residual).
    static func isClaudeRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop"
                || ($0.localizedName?.localizedCaseInsensitiveContains("Claude") == true
                    && $0.bundleURL?.lastPathComponent == "Claude.app")
        }
    }

    /// Merge `agent-canvas` into Claude Desktop’s config file.
    ///
    /// **Do not call while Claude is running** if possible — Claude rewrites
    /// `claude_desktop_config.json` on launch/quit and has been observed to drop
    /// `mcpServers` when it flushes preferences.
    static func connectClaudeDesktop(command: String, allowWhileRunning: Bool = false) -> Result {
        guard isClaudeDesktopInstalled() || FileManager.default.fileExists(
            atPath: claudeConfigURL.deletingLastPathComponent().path
        ) else {
            return Result(
                ok: false,
                message: "Claude Desktop not found — install it, or use Copy MCP Config"
            )
        }

        if isClaudeRunning() && !allowWhileRunning {
            return Result(
                ok: false,
                message: "Quit Claude Desktop completely first (Claude → Quit). "
                    + "If it’s running, it may overwrite the config and remove agent-canvas."
            )
        }

        let result = mergeServerIntoJSONFile(
            url: claudeConfigURL,
            command: command,
            createParents: true
        )
        guard result.ok else { return result }

        // Verify on disk — false “success” is worse than a hard error.
        if !isRegisteredInClaude() {
            return Result(
                ok: false,
                message: "Wrote config but agent-canvas is not present after verify — "
                    + "open \(claudeConfigURL.path) and check mcpServers"
            )
        }

        return Result(
            ok: true,
            message: "agent-canvas is in Claude’s config. Open Claude Desktop now "
                + "(fully quit first if it was open). Check + → Connectors, not Plugins."
        )
    }

    static func openClaudeDesktopApp() {
        if let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.anthropic.claudefordesktop"
        ) {
            NSWorkspace.shared.open(app)
        } else if FileManager.default.fileExists(atPath: "/Applications/Claude.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
        }
    }

    /// Ask Claude to quit (best-effort). User may still need to confirm.
    @discardableResult
    static func requestClaudeQuit() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop"
        }
        guard !apps.isEmpty else { return true }
        for app in apps {
            app.terminate()
        }
        return true
    }

    static func isRegisteredInClaude() -> Bool {
        isServerRegistered(in: claudeConfigURL)
    }

    /// True when this client already has agent-canvas registered and the helper binary exists.
    /// Used to skip full setup and label the menu.
    static func isConnected(_ client: ConnectWizardClient) -> Bool {
        let binaryOK = AgentCanvasPaths.mcpBinaryResolved().exists
        switch client {
        case .cursor:
            return binaryOK && isRegisteredInCursor()
        case .claude:
            return binaryOK && isRegisteredInClaude()
        case .chatgpt:
            // No local stdio path — never “connected” in the same sense.
            return false
        case .manual:
            // Manual clients aren’t tracked on disk.
            return false
        }
    }

    /// Human-readable summary of Claude MCP registration for the wizard UI.
    static func claudeRegistrationSummary() -> String {
        let url = claudeConfigURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Config file missing — will be created on write"
        }
        if let servers = obj["mcpServers"] as? [String: Any] {
            if let entry = servers[serverName] as? [String: Any] {
                let cmd = entry["command"] as? String ?? "?"
                return "Registered · command=\(cmd)"
            }
            let names = servers.keys.sorted().joined(separator: ", ")
            return "mcpServers present but no agent-canvas (have: \(names.isEmpty ? "none" : names))"
        }
        return "Config has no mcpServers key (Claude may have rewritten preferences only)"
    }

    // MARK: - Shared merge

    private static func isServerRegistered(in url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let servers = obj["mcpServers"] as? [String: Any], servers[serverName] != nil {
            return true
        }
        // Some Cursor files use top-level server keys only.
        return obj[serverName] != nil
    }

    private static func mergeServerIntoJSONFile(
        url: URL,
        command: String,
        createParents: Bool
    ) -> Result {
        let fm = FileManager.default
        if createParents {
            try? fm.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        var root: [String: Any] = [:]
        if fm.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            root = obj
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers[serverName] = serverConfig(command: command)
        root["mcpServers"] = servers

        guard JSONSerialization.isValidJSONObject(root),
              let out = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
              )
        else {
            return Result(ok: false, message: "Failed to encode MCP config JSON")
        }

        do {
            try out.write(to: url, options: .atomic)
            return Result(ok: true, message: "Updated \(url.path)")
        } catch {
            return Result(ok: false, message: "Could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

private extension MCPClientInstall.Result {
    func mapMessage(_ transform: (String) -> String) -> MCPClientInstall.Result {
        MCPClientInstall.Result(ok: ok, message: ok ? transform(message) : message)
    }
}

// MARK: - Binary discovery

enum AgentCanvasPaths {
    /// Prefer a real executable on disk so agent hosts can spawn it.
    /// Order: env override → bundled helper → Homebrew / PATH → nearby cargo builds (dev).
    static func preferredMCPBinaryPath() -> String {
        var candidates: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["AGENT_CANVAS_MCP"],
           !envPath.isEmpty
        {
            candidates.append(envPath)
        }

        // Shipped next to the host: AgentCanvas.app/Contents/MacOS/agent-canvas-mcp
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "agent-canvas-mcp")?.path {
            candidates.append(bundled)
        } else if let macos = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(macos.appendingPathComponent("agent-canvas-mcp").path)
        }

        candidates += [
            "/opt/homebrew/bin/agent-canvas-mcp",
            "/usr/local/bin/agent-canvas-mcp",
        ]

        if let which = shellWhich("agent-canvas-mcp") {
            candidates.append(which)
        }

        // Dev convenience: cargo outputs near the app or under common checkouts.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates += [
            "\(home)/code/velox/agent-canvas/target/release/agent-canvas-mcp",
            "\(home)/code/velox/agent-canvas/target/debug/agent-canvas-mcp",
            "\(home)/src/velox/agent-canvas/target/release/agent-canvas-mcp",
            "\(home)/src/velox/agent-canvas/target/debug/agent-canvas-mcp",
        ]
        if let appURL = Bundle.main.bundleURL as URL? {
            var dir = appURL.deletingLastPathComponent()
            for _ in 0..<8 {
                for config in ["release", "debug"] {
                    candidates.append(
                        dir.appendingPathComponent("target/\(config)/agent-canvas-mcp").path
                    )
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Prefer the conventional bundled name when nothing is on disk yet.
        if let macos = Bundle.main.executableURL?.deletingLastPathComponent() {
            return macos.appendingPathComponent("agent-canvas-mcp").path
        }
        return "agent-canvas-mcp"
    }

    static func mcpBinaryResolved() -> (path: String, exists: Bool) {
        let path = preferredMCPBinaryPath()
        let exists = FileManager.default.isExecutableFile(atPath: path)
        return (path, exists)
    }

    private static func shellWhich(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch {
            return nil
        }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var buildVersion: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
