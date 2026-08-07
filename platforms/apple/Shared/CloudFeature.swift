import Foundation

/// Pre-release cloud publish / subscribe UI + host hooks.
///
/// Matches MCP gate:
/// - **Release** builds: always off (unless you add a compile flag later).
/// - **Debug**: requires `AGENT_CANVAS_CLOUD_PUBLISH=1` **or** the Settings toggle
///   (`UserDefaults` key below) so Xcode runs don't need a shell env.
enum CloudFeature {
    static let envName = "AGENT_CANVAS_CLOUD_PUBLISH"
    static let defaultsKey = "agentCanvas.cloudPublishEnabled"

    /// Whether cloud UI and host publish/subscribe actions may run.
    static var isEnabled: Bool {
        #if DEBUG
        if envEnabled { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
        #else
        return false
        #endif
    }

    static var envEnabled: Bool {
        guard let raw = ProcessInfo.processInfo.environment[envName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return false }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    /// Debug Settings toggle (persisted). No-op effect in Release builds.
    static var userToggleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var statusDescription: String {
        #if DEBUG
        if envEnabled { return "On (env \(envName)=1)" }
        if userToggleEnabled { return "On (Settings toggle)" }
        return "Off — set \(envName)=1 or enable in Cloud settings"
        #else
        return "Unavailable in Release builds"
        #endif
    }
}
