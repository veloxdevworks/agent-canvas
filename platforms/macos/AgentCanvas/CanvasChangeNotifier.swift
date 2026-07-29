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

    func configure() {
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Request alert permission. Returns whether the user granted authorization.
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("AgentCanvas: notification authorization failed: \(error.localizedDescription)")
            return false
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
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
}
