import Foundation
import BackgroundTasks
import WidgetKit

/// Pulls cloud subscriptions into App Group storage and reloads WidgetKit.
@MainActor
final class SubscriptionSync: ObservableObject {
    static let shared = SubscriptionSync()
    static let backgroundTaskIdentifier = "com.velox.agentcanvas.ios.refresh"

    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var statusLine: String = "Ready"

    enum Reason: String {
        case launch
        case foreground
        case signIn
        case manual
        case timer
        case background
        case subscribe
    }

    private var foregroundTimer: Timer?
    private var lastPollAt: [String: Date] = [:]

    private init() {}

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await shared.handleBackgroundRefresh(refresh)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("AgentCanvas iOS: BGAppRefresh schedule failed: \(error.localizedDescription)")
        }
    }

    func startForegroundPolling() {
        stopForegroundPolling()
        let interval = TimeInterval(max(15, CloudConfigStore.load().defaultPollIntervalSeconds))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll(reason: .timer)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        foregroundTimer = timer
    }

    func stopForegroundPolling() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }

    func syncAll(reason: Reason) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let subs = CloudSubscriptionStore.load().filter(\.enabled)
        guard !subs.isEmpty else {
            statusLine = "No subscriptions"
            lastSyncAt = Date()
            lastError = nil
            return
        }

        statusLine = "Syncing \(subs.count)…"
        var errors: [String] = []
        for sub in subs {
            do {
                try await CloudAPIClient.fetchSubscription(sub)
            } catch {
                errors.append("\(sub.canvas): \(CloudAPIClient.userFacingMessage(for: error))")
            }
        }
        lastSyncAt = Date()
        if errors.isEmpty {
            lastError = nil
            statusLine = "Synced \(reason.rawValue) · \(lastSyncAt!.formatted(date: .omitted, time: .shortened))"
        } else {
            lastError = errors.joined(separator: "\n")
            statusLine = "Sync finished with \(errors.count) error(s)"
        }
        CanvasStorage.reloadAllTimelines()
    }

    /// One-shot subscribe: upsert URL for slot, fetch, reload that widget.
    func subscribe(slugOrURL: String, address: CanvasAddress) async throws {
        let config = CloudConfigStore.load()
        let trimmed = slugOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudAPIClient.APIError.message("Enter a slug or canvas URL.")
        }

        let urlString: String
        let slug: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            urlString = trimmed
            slug = URL(string: trimmed)?.lastPathComponent ?? trimmed
        } else {
            slug = trimmed
            guard let url = config.canvasURL(slug: slug) else {
                throw CloudAPIClient.APIError.badURL
            }
            urlString = url.absoluteString
        }

        let sub = CloudSubscription(
            canvas: address.rawValue,
            url: urlString,
            pollIntervalSeconds: config.defaultPollIntervalSeconds,
            enabled: true,
            etag: nil,
            lastFetchAt: nil,
            lastError: nil,
            lastStatusCode: nil
        )
        try CloudSubscriptionStore.upsert(sub)
        try await CloudAPIClient.fetchSubscription(sub)
        CanvasStorage.reload(address: address)
        lastSyncAt = Date()
        lastError = nil
        statusLine = "Subscribed \(slug) → \(address.rawValue)"
    }

    func unsubscribe(address: CanvasAddress, clearContent: Bool) throws {
        try CloudSubscriptionStore.remove(canvas: address.rawValue)
        if clearContent {
            try CanvasStorage.clear(address: address)
        } else {
            CanvasStorage.reload(address: address)
        }
        statusLine = "Unsubscribed \(address.rawValue)"
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()
        let syncTask = Task { await syncAll(reason: .background) }
        task.expirationHandler = {
            syncTask.cancel()
        }
        await syncTask.value
        task.setTaskCompleted(success: lastError == nil)
    }
}
