import Foundation

/// Glance chrome for a subscribed widget (PLAT-103 / US-039).
///
/// Local (non-subscribed) slots resolve to `nil` and keep existing tile chrome.
/// Subscribed tiles show the shared slug and last successful pull. Content is
/// never wiped when a pull fails — this is a warning only.
///
/// **Stale when**
/// - the last pull recorded an error, or
/// - the last successful pull is older than `staleAfter`.
///
/// **`staleAfter`:** 15 minutes, or 3× the subscription poll interval if that
/// is longer, so a slow poller is not marked stale between ticks.
struct SubscriptionProvenance: Equatable {
    enum StaleReason: Equatable {
        case pullFailed
        case lastSyncTooOld
    }

    /// Documented age floor (PLAT-103).
    static let defaultStaleAfter: TimeInterval = 15 * 60

    let slug: String
    let lastSyncedAt: Date?
    let lastError: String?
    let isStale: Bool
    let staleReason: StaleReason?
    let staleAfter: TimeInterval

    static func staleAfter(pollIntervalSeconds: Int) -> TimeInterval {
        max(defaultStaleAfter, TimeInterval(max(15, pollIntervalSeconds) * 3))
    }

    static func slug(fromURL urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let url = URL(string: trimmed) {
            let last = url.lastPathComponent
            if !last.isEmpty, last != "/" {
                return last
            }
        }
        return trimmed
    }

    static func resolve(
        subscription: CloudSubscription?,
        now: Date = Date()
    ) -> SubscriptionProvenance? {
        guard let subscription else { return nil }
        let threshold = staleAfter(pollIntervalSeconds: subscription.pollIntervalSeconds)
        let lastSynced = subscription.lastSuccessAt
            ?? (subscription.lastError == nil ? subscription.lastFetchAt : nil)
        let failing = !(subscription.lastError ?? "").isEmpty
        let aged = lastSynced.map { now.timeIntervalSince($0) > threshold } ?? false
        let reason: StaleReason?
        if failing {
            reason = .pullFailed
        } else if aged {
            reason = .lastSyncTooOld
        } else {
            reason = nil
        }
        return SubscriptionProvenance(
            slug: slug(fromURL: subscription.url),
            lastSyncedAt: lastSynced,
            lastError: subscription.lastError,
            isStale: reason != nil,
            staleReason: reason,
            staleAfter: threshold
        )
    }

    /// Same subscription chrome for every placed family of this definition.
    static func resolve(for address: CanvasAddress, now: Date = Date()) -> SubscriptionProvenance? {
        resolve(subscription: CloudSubscriptionStore.subscription(for: address.rawValue), now: now)
    }

    /// Absolute time — WidgetKit freezes snapshots, so relative "N min ago" goes stale.
    static func formattedSyncTime(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.year(.twoDigits).month(.abbreviated).day().hour().minute())
    }

    /// Compact footer, e.g. `standups · Aug 15, 2:04 PM` or `standups · outdated`.
    var compactLine: String {
        var parts = [slug]
        if let lastSyncedAt {
            parts.append(Self.formattedSyncTime(lastSyncedAt))
        } else if !isStale {
            parts.append("not yet synced")
        }
        if isStale {
            parts.append("outdated")
        }
        return parts.joined(separator: " · ")
    }

    var accessibilityLabel: String {
        if isStale {
            if staleReason == .pullFailed, let lastError, !lastError.isEmpty {
                return "Subscribed to \(slug). Desktop view may be outdated. \(lastError)"
            }
            return "Subscribed to \(slug). Desktop view may be outdated."
        }
        if let lastSyncedAt {
            return "Subscribed to \(slug). Last synced \(Self.formattedSyncTime(lastSyncedAt))."
        }
        return "Subscribed to \(slug). Not yet synced."
    }
}
