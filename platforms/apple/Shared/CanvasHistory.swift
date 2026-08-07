import Foundation

/// Local per-canvas version history under `~/.velox/canvas/history/{id}/`.
/// Keep layout and index schema aligned with Rust `agent_canvas_core::history`.
enum CanvasHistory {
    static let maxEntries = 30

    enum Source: String, Codable {
        case mcp
        case host
        case restore
        case clear
        case seed
        case cloud
        case unknown

        var displayName: String {
            switch self {
            case .mcp: return "MCP"
            case .host: return "Host"
            case .restore: return "Restore"
            case .clear: return "Clear"
            case .seed: return "Seed"
            case .cloud: return "Cloud"
            case .unknown: return "Unknown"
            }
        }
    }

    struct Entry: Identifiable, Codable, Equatable {
        var id: String
        var savedAt: Date
        var title: String?
        var source: Source
        var byteSize: UInt64
        var sectionCount: Int

        enum CodingKeys: String, CodingKey {
            case id, savedAt, title, source, byteSize, sectionCount
        }
    }

    private struct Index: Codable {
        var version: Int
        var entries: [Entry]
    }

    // MARK: - Paths

    static func historyRoot() -> URL {
        CanvasStorage.applicationSupportRoot
            .appendingPathComponent(AgentCanvasConstants.historySubdir, isDirectory: true)
    }

    static func directory(for address: CanvasAddress) -> URL {
        historyRoot().appendingPathComponent(address.rawValue, isDirectory: true)
    }

    private static func indexURL(for address: CanvasAddress) -> URL {
        directory(for: address).appendingPathComponent("index.json")
    }

    private static func snapshotURL(for address: CanvasAddress, entryId: String) -> URL {
        directory(for: address).appendingPathComponent("\(entryId).json")
    }

    // MARK: - Codec

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

    // MARK: - Public API

    static func list(address: CanvasAddress) -> [Entry] {
        loadIndex(address: address).entries
    }

    static func load(address: CanvasAddress, entryId: String) -> CanvasDocument? {
        let url = snapshotURL(for: address, entryId: entryId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CanvasDocument.self, from: data)
    }

    /// Archive `previous` when it differs from `incoming` and is non-empty.
    @discardableResult
    static func archiveIfNeeded(
        address: CanvasAddress,
        previous: CanvasDocument,
        incoming: CanvasDocument,
        source: Source
    ) -> String? {
        if previous.isEmptyContent && incoming.isEmptyContent { return nil }
        if contentEqual(previous, incoming) { return nil }
        if previous.isEmptyContent { return nil }

        let dir = directory(for: address)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("AgentCanvas: history mkdir failed: \(error)")
            return nil
        }

        let entryId = newEntryId()
        let snapURL = snapshotURL(for: address, entryId: entryId)
        do {
            let data = try encoder.encode(previous)
            try data.write(to: snapURL, options: .atomic)
            var index = loadIndex(address: address)
            index.entries.removeAll { $0.id == entryId }
            let entry = Entry(
                id: entryId,
                savedAt: Date(),
                title: previous.title,
                source: source,
                byteSize: UInt64(data.count),
                sectionCount: previous.sections.count
            )
            index.entries.insert(entry, at: 0)
            prune(&index, address: address)
            try saveIndex(index, address: address)
            return entryId
        } catch {
            NSLog("AgentCanvas: history archive failed: \(error)")
            return nil
        }
    }

    static func delete(address: CanvasAddress, entryId: String) throws {
        let url = snapshotURL(for: address, entryId: entryId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var index = loadIndex(address: address)
        index.entries.removeAll { $0.id == entryId }
        try saveIndex(index, address: address)
    }

    /// Restore a history snapshot as the current canvas (archives current first).
    static func restore(address: CanvasAddress, entryId: String) throws {
        guard let snap = load(address: address, entryId: entryId) else {
            throw NSError(
                domain: "AgentCanvas.History",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "History entry not found"]
            )
        }
        try CanvasStorage.write(snap, address: address, source: .restore)
        CanvasStorage.reload(address: address)
    }

    // MARK: - Internals

    static func contentEqual(_ a: CanvasDocument, _ b: CanvasDocument) -> Bool {
        a.title == b.title
            && a.cover == b.cover
            && a.onOpen == b.onOpen
            && a.sections == b.sections
            && a.detail == b.detail
    }

    private static func newEntryId() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: Date())
        let suffix = String(format: "%06x", UInt32.random(in: 0...0xFFFFFF))
        return "\(stamp)-\(suffix)"
    }

    private static func loadIndex(address: CanvasAddress) -> Index {
        let url = indexURL(for: address)
        if let data = try? Data(contentsOf: url),
           let index = try? decoder.decode(Index.self, from: data)
        {
            return index
        }
        return rebuildIndex(address: address)
    }

    private static func rebuildIndex(address: CanvasAddress) -> Index {
        let dir = directory(for: address)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Index(version: 1, entries: [])
        }

        var entries: [Entry] = []
        for url in files {
            guard url.pathExtension == "json", url.lastPathComponent != "index.json" else { continue }
            let entryId = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let doc = try? decoder.decode(CanvasDocument.self, from: data)
            else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append(
                Entry(
                    id: entryId,
                    savedAt: values?.contentModificationDate ?? Date(),
                    title: doc.title,
                    source: .unknown,
                    byteSize: UInt64(values?.fileSize ?? data.count),
                    sectionCount: doc.sections.count
                )
            )
        }
        entries.sort { $0.savedAt > $1.savedAt }
        let index = Index(version: 1, entries: entries)
        try? saveIndex(index, address: address)
        return index
    }

    private static func saveIndex(_ index: Index, address: CanvasAddress) throws {
        let dir = directory(for: address)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var copy = index
        copy.version = 1
        let data = try encoder.encode(copy)
        try data.write(to: indexURL(for: address), options: .atomic)
    }

    private static func prune(_ index: inout Index, address: CanvasAddress) {
        while index.entries.count > maxEntries {
            guard let old = index.entries.popLast() else { break }
            let url = snapshotURL(for: address, entryId: old.id)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
