import AppKit
import Foundation
import ServiceManagement

/// Open-at-login via `SMAppService.mainApp` (macOS 13+ Login Items).
enum LaunchAtLogin {
    /// True when Launch Services will start the host at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Registers or unregisters the main app as a login item.
    /// - Returns: Status after the attempt (may be `.requiresApproval` until the user allows it).
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> SMAppService.Status {
        if enabled {
            if status == .enabled { return status }
            try SMAppService.mainApp.register()
        } else {
            if status == .notRegistered { return status }
            try SMAppService.mainApp.unregister()
        }
        return SMAppService.mainApp.status
    }

    /// Opens System Settings → General → Login Items.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Short note for Settings when registration needs user approval or failed.
    static func statusNote(for status: SMAppService.Status, error: Error? = nil) -> String {
        if let error {
            return "Couldn’t update startup setting: \(error.localizedDescription)"
        }
        switch status {
        case .requiresApproval:
            return "Allow Agent Canvas under System Settings → General → Login Items & Extensions."
        case .notFound:
            return "Startup registration isn’t available for this build. Try installing Agent Canvas in Applications."
        case .enabled, .notRegistered:
            return ""
        @unknown default:
            return ""
        }
    }
}
