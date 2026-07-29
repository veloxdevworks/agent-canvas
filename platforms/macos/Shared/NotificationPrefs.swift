import Foundation

/// User preferences for content-change system notifications (host Settings).
enum NotificationPrefs {
    static let enabledKey = "agentCanvas.notificationsEnabled"
    static let mutedKey = "agentCanvas.mutedCanvasIds"

    /// Master switch — default off (opt-in).
    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func isMuted(_ address: CanvasAddress) -> Bool {
        mutedIds.contains(address.rawValue)
    }

    static func setMuted(_ address: CanvasAddress, _ muted: Bool) {
        var ids = mutedIds
        if muted {
            ids.insert(address.rawValue)
        } else {
            ids.remove(address.rawValue)
        }
        mutedIds = ids
    }

    private static var mutedIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: mutedKey) }
    }
}
