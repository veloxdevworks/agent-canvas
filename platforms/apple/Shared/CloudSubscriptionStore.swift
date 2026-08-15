import Foundation

/// Per-slot URL subscription. Pull daemon records ETag / last fetch / last success / last error.
struct CloudSubscription: Codable, Equatable, Identifiable {
    var canvas: String
    /// Full URL to JSON (usually `…/api/v1/canvases/{slug}`).
    var url: String
    var pollIntervalSeconds: Int
    var enabled: Bool
    var etag: String?
    /// Last pull attempt (success or failure).
    var lastFetchAt: Date?
    var lastError: String?
    var lastStatusCode: Int?
    /// Last successful pull (HTTP 304 or 2xx). Used for widget last-synced + staleness.
    var lastSuccessAt: Date? = nil

    var id: String { canvas }
}

enum CloudSubscriptionStore {
    private static var fileURL: URL {
        CanvasStorage.applicationSupportRoot
            .appendingPathComponent(AgentCanvasConstants.subscriptionsFileName)
    }

    private struct File: Codable {
        var subscriptions: [CloudSubscription]
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func load() -> [CloudSubscription] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(File.self, from: data)
        else { return [] }
        return file.subscriptions
    }

    static func save(_ items: [CloudSubscription]) throws {
        CanvasStorage.ensureDirectories()
        let data = try encoder.encode(File(subscriptions: items.sorted { $0.canvas < $1.canvas }))
        try data.write(to: fileURL, options: .atomic)
    }

    static func upsert(_ sub: CloudSubscription) throws {
        var normalized = sub
        normalized.canvas = canonicalCanvasId(sub.canvas)
        var items = load().filter { !recordsMatch($0.canvas, normalized.canvas) }
        items.append(normalized)
        try save(items)
    }

    static func remove(canvas: String) throws {
        try save(load().filter { !recordsMatch($0.canvas, canvas) })
    }

    static func subscription(for canvas: String) -> CloudSubscription? {
        let items = load()
        if let exact = items.first(where: { $0.canvas == canvas }) {
            return exact
        }
        return items.first { recordsMatch($0.canvas, canvas) }
    }

    /// Persist and look up by definition id (`one`…`twelve`).
    /// Leftover size-baked keys (`md-one`) still match one / two / three.
    static func canonicalCanvasId(_ raw: String) -> String {
        CanvasAddress.parse(raw)?.rawValue ?? raw
    }

    static func recordsMatch(_ stored: String, _ query: String) -> Bool {
        if stored == query { return true }
        guard let a = CanvasAddress.parse(stored), let b = CanvasAddress.parse(query) else {
            return false
        }
        return a == b
    }
}
