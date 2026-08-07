import Foundation

/// Local share index — mirrors Rust `shares.json` (no tokens).
struct CloudShareRecord: Codable, Equatable, Identifiable {
    var canvas: String
    var slug: String
    var publicUrl: String
    var apiUrl: String
    var sharedAt: Date
    var lastVersion: UInt32?
    var lastEtag: String?
    /// `public` | `org` | `private`
    var visibility: String?
    var orgId: String?
    var orgName: String?
    /// When true, host auto-PUTs after local canvas reloads (MCP write).
    var autoPushUpdates: Bool?

    var id: String { slug }

    var resolvedVisibility: String { visibility ?? "public" }
    var resolvedAutoPush: Bool { autoPushUpdates ?? false }
}

struct CloudOrganization: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var slug: String?
}

enum CloudShareIndex {
    private static var fileURL: URL {
        CanvasStorage.applicationSupportRoot
            .appendingPathComponent(AgentCanvasConstants.sharesFileName)
    }

    private struct File: Codable {
        var shares: [CloudShareRecord]
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

    static func load() -> [CloudShareRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(File.self, from: data)
        else { return [] }
        return file.shares
    }

    static func save(_ shares: [CloudShareRecord]) throws {
        CanvasStorage.ensureDirectories()
        let data = try encoder.encode(File(shares: shares.sorted { $0.slug < $1.slug }))
        try data.write(to: fileURL, options: .atomic)
    }

    static func upsert(_ record: CloudShareRecord) throws {
        var shares = load().filter { $0.slug != record.slug && $0.canvas != record.canvas }
        shares.append(record)
        try save(shares)
    }

    static func remove(slug: String) throws {
        try save(load().filter { $0.slug != slug })
    }

    static func record(forCanvas canvas: String) -> CloudShareRecord? {
        load().first { $0.canvas == canvas }
    }

    static func record(forSlug slug: String) -> CloudShareRecord? {
        load().first { $0.slug == slug }
    }

    static func setAutoPush(canvas: String, enabled: Bool) throws {
        guard var record = record(forCanvas: canvas) else { return }
        record.autoPushUpdates = enabled
        try upsert(record)
    }
}
