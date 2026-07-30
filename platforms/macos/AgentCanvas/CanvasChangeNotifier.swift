import AppKit
import Foundation
import UserNotifications

/// Coalesces content-change events and posts local macOS notifications.
@MainActor
final class CanvasChangeNotifier: NSObject {
    static let shared = CanvasChangeNotifier()

    nonisolated static let categoryId = "canvas.contentChanged"
    nonisolated static let canvasIdKey = "canvasId"
    nonisolated static let canvasIdsKey = "canvasIds"

    private var pending: [(address: CanvasAddress, title: String)] = []
    private var flushWorkItem: DispatchWorkItem?
    private let coalesceInterval: TimeInterval = 2.0

    /// Result of turning notifications on from Settings.
    struct EnableResult: Equatable {
        var enabled: Bool
        /// Caption under the toggle (empty when quiet success).
        var note: String
        var showOpenSettings: Bool

        static let disabled = EnableResult(enabled: false, note: "", showOpenSettings: false)
    }

    func configure() {
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Whether the OS will deliver alert/banner notifications for this app.
    func isAuthorizedForAlerts() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.canDeliverAlerts(settings)
    }

    /// If the in-app preference is on but the OS blocked us, turn the pref off and explain.
    func reconcilePreferenceWithSystem() async -> EnableResult {
        guard NotificationPrefs.notificationsEnabled else {
            return .disabled
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if Self.canDeliverAlerts(settings) {
            return EnableResult(enabled: true, note: "", showOpenSettings: false)
        }
        NotificationPrefs.notificationsEnabled = false
        return Self.deniedResult(status: settings.authorizationStatus)
    }

    /// Activate the app, request permission if needed, persist pref, and send a test banner.
    func enableFromUser() async -> EnableResult {
        NSApp.activate(ignoringOtherApps: true)

        var settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            } catch {
                NSLog("AgentCanvas: notification authorization failed: \(error.localizedDescription)")
                NotificationPrefs.notificationsEnabled = false
                return EnableResult(
                    enabled: false,
                    note: "Could not request notification permission: \(error.localizedDescription)",
                    showOpenSettings: true
                )
            }
            settings = await UNUserNotificationCenter.current().notificationSettings()
        case .denied:
            NotificationPrefs.notificationsEnabled = false
            return Self.deniedResult(status: .denied)
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        guard Self.canDeliverAlerts(settings) else {
            NotificationPrefs.notificationsEnabled = false
            return Self.deniedResult(status: settings.authorizationStatus)
        }

        NotificationPrefs.notificationsEnabled = true
        if let scheduleError = await scheduleTestNotification() {
            return EnableResult(
                enabled: true,
                note: "Permission granted, but a test notification failed: \(scheduleError). Check System Settings → Notifications.",
                showOpenSettings: true
            )
        }
        return EnableResult(
            enabled: true,
            note: "Notifications enabled — you should see a test banner.",
            showOpenSettings: false
        )
    }

    func disableFromUser() {
        NotificationPrefs.notificationsEnabled = false
        pending.removeAll()
        flushWorkItem?.cancel()
        flushWorkItem = nil
    }

    /// Opens System Settings to the Notifications pane (best-effort URL).
    nonisolated static func openSystemNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func enqueueChange(address: CanvasAddress, title: String) {
        guard NotificationPrefs.notificationsEnabled else { return }
        guard !NotificationPrefs.isMuted(address) else { return }
        pending.append((address, title))
        scheduleFlush()
    }

    func enqueueChanges(_ items: [(CanvasAddress, String)]) {
        for (address, title) in items {
            enqueueChange(address: address, title: title)
        }
    }

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flush()
            }
        }
        flushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
    }

    private func flush() {
        flushWorkItem = nil
        guard NotificationPrefs.notificationsEnabled else {
            pending.removeAll()
            return
        }

        var order: [CanvasAddress] = []
        var titles: [CanvasAddress: String] = [:]
        for item in pending {
            if titles[item.address] == nil {
                order.append(item.address)
            }
            titles[item.address] = item.title
        }
        pending.removeAll()

        let items = order.compactMap { address -> (CanvasAddress, String)? in
            guard !NotificationPrefs.isMuted(address), let title = titles[address] else { return nil }
            return (address, title)
        }
        guard !items.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.categoryId
        content.sound = .default

        if items.count == 1, let only = items.first {
            content.title = only.1
            content.body = "\(only.0.displayName) updated"
            content.userInfo = [
                Self.canvasIdKey: only.0.rawValue,
                Self.canvasIdsKey: [only.0.rawValue],
            ]
        } else {
            content.title = "\(items.count) canvases updated"
            content.body = items.map(\.1).joined(separator: ", ")
            content.userInfo = [
                Self.canvasIdKey: items[0].0.rawValue,
                Self.canvasIdsKey: items.map(\.0.rawValue),
            ]
        }

        let request = UNNotificationRequest(
            identifier: "canvas-change-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard Self.canDeliverAlerts(settings) else {
                await MainActor.run {
                    NotificationPrefs.notificationsEnabled = false
                    NSLog("AgentCanvas: notification delivery blocked by system; preference cleared")
                }
                return
            }
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                NSLog("AgentCanvas: schedule notification failed: \(error.localizedDescription)")
            }
        }
    }

    /// Display title for a notification line (document title, else slot name).
    nonisolated static func displayTitle(for document: CanvasDocument, address: CanvasAddress) -> String {
        if let title = document.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return address.displayName
    }

    nonisolated static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        guard let id = info[canvasIdKey] as? String, CanvasAddress(rawValue: id) != nil else { return }
        DispatchQueue.main.async {
            AppDelegate.pendingDetailId = id
            NotificationCenter.default.post(name: .agentCanvasOpenDetail, object: id)
            AppDelegate.hideSettingsWindows()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Private

    private static func canDeliverAlerts(_ settings: UNNotificationSettings) -> Bool {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private static func deniedResult(status: UNAuthorizationStatus) -> EnableResult {
        let note: String
        switch status {
        case .denied:
            note = "Notification permission is off for Agent Canvas. Enable it in System Settings → Notifications."
        case .notDetermined:
            note = "Notification permission was not granted."
        default:
            note = "Notifications are disabled for Agent Canvas in System Settings → Notifications."
        }
        return EnableResult(enabled: false, note: note, showOpenSettings: true)
    }

    private func scheduleTestNotification() async -> String? {
        let content = UNMutableNotificationContent()
        content.title = "Agent Canvas"
        content.body = "Notifications are on. You’ll be notified when an agent updates a canvas."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "canvas-notifications-enabled-test",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return nil
        } catch {
            NSLog("AgentCanvas: test notification failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
