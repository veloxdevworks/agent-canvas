import Foundation

/// Per-slot URL subscription (PLAT-83 UI ahead of full pull daemon).
struct CloudSubscription: Codable, Equatable, Identifiable {
    var canvas: String
    /// Full URL to JSON (usually `…/api/v1/canvases/{slug}`).
    var url: String
    var pollIntervalSeconds: Int
    var enabled: Bool
    var etag: String?
    var lastFetchAt: Date?
    var lastError: String?
    var lastStatusCode: Int?

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
        var items = load().filter { $0.canvas != sub.canvas }
        items.append(sub)
        try save(items)
    }

    static func remove(canvas: String) throws {
        try save(load().filter { $0.canvas != canvas })
    }

    static func subscription(for canvas: String) -> CloudSubscription? {
        load().first { $0.canvas == canvas }
    }
}
