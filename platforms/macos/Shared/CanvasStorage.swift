import Foundation
import WidgetKit
#if canImport(Darwin)
import Darwin
#endif

/// Reads/writes canvas JSON under `~/.velox/canvas`.
/// MCP and host share the same tree; widgets use temporary-exception + real user home.
enum CanvasStorage {
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

    /// Real login home — not the App Sandbox container home.
    static var realUserHome: URL {
        #if canImport(Darwin)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/.velox/canvas` — keep name `applicationSupportRoot` for call-site stability.
    static var applicationSupportRoot: URL {
        realUserHome
            .appendingPathComponent(AgentCanvasConstants.veloxDirName, isDirectory: true)
            .appendingPathComponent(AgentCanvasConstants.canvasDirName, isDirectory: true)
    }

    static var applicationSupportCanvases: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.canvasesSubdir, isDirectory: true)
    }

    static var previewsRoot: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.previewsSubdir, isDirectory: true)
    }

    static var assetsRoot: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.assetsSubdir, isDirectory: true)
    }

    static func applicationSupportURL(for address: CanvasAddress) -> URL {
        applicationSupportCanvases.appendingPathComponent(address.fileName)
    }

    static func lastRenderURL(for address: CanvasAddress) -> URL {
        applicationSupportCanvases.appendingPathComponent("\(address.rawValue).render.json")
    }

    static func previewPNGURL(for address: CanvasAddress) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).png")
    }

    static func previewTokenURL(for address: CanvasAddress) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).token")
    }

    static func previewMetaURL(for address: CanvasAddress) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).meta.json")
    }

    static var previewRequestURL: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.previewRequestFileName)
    }

    /// Phase B: widget reports what it actually showed after clipping.
    static func writeLastRender(_ report: LastRenderReport, address: CanvasAddress) {
        ensureDirectories()
        do {
            let data = try encoder.encode(report)
            try data.write(to: lastRenderURL(for: address), options: .atomic)
        } catch {
            NSLog("AgentCanvas: writeLastRender failed: \(error)")
        }
    }

    static func loadLastRender(address: CanvasAddress) -> LastRenderReport? {
        let url = lastRenderURL(for: address)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LastRenderReport.self, from: data)
    }

    @discardableResult
    static func ensureDirectories() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportCanvases,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: previewsRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: assetsRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: CanvasHistory.historyRoot(),
                withIntermediateDirectories: true
            )
            return true
        } catch {
            NSLog("AgentCanvas: ensureDirectories failed (ok if widget): \(error)")
            return false
        }
    }

    static func load(address: CanvasAddress) -> CanvasDocument {
        let url = applicationSupportURL(for: address)
        if let doc = decode(from: url) {
            return doc
        }
        return .empty
    }

    private static func decode(from url: URL) -> CanvasDocument? {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(CanvasDocument.self, from: data)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError
            {
                return nil
            }
            NSLog("AgentCanvas: read/decode failed \(url.path): \(error)")
            return nil
        }
    }

    static func write(
        _ document: CanvasDocument,
        address: CanvasAddress,
        source: CanvasHistory.Source = .host
    ) throws {
        ensureDirectories()
        let previous = load(address: address)
        var doc = document
        doc.version = CanvasDocument.schemaVersion
        doc.updatedAt = Date()
        CanvasHistory.archiveIfNeeded(
            address: address,
            previous: previous,
            incoming: doc,
            source: source
        )
        let data = try encoder.encode(doc)
        try data.write(to: applicationSupportURL(for: address), options: .atomic)
    }

    static func reloadAllTimelines() {
        for kind in CanvasAddress.allKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func reload(address: CanvasAddress) {
        WidgetCenter.shared.reloadTimelines(ofKind: address.widgetKind)
    }

    /// Host convenience: ensure dirs exist and reload every kind.
    static func mirrorAllAndReload() {
        ensureDirectories()
        reloadAllTimelines()
    }

    static func clear(address: CanvasAddress) throws {
        try write(.empty, address: address, source: .clear)
        reload(address: address)
    }

    static func clearAll() throws {
        for address in CanvasAddress.allCases {
            try write(.empty, address: address, source: .clear)
        }
        reloadAllTimelines()
    }

    static var reloadRequestURL: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.reloadRequestFileName)
    }

    /// MCP writes size-first id on first line (e.g. `md-one`).
    /// Returns `.all` when a reload was requested without a parsable canvas id.
    static func consumeReloadRequest() -> ReloadRequest? {
        let url = reloadRequestURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        try? FileManager.default.removeItem(at: url)
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        let key = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = CanvasAddress(rawValue: key) {
            return .one(address)
        }
        for token in key.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            if let address = CanvasAddress(rawValue: String(token)) {
                return .one(address)
            }
        }
        // Timestamp-only or empty body — reload everything.
        return .all
    }

    /// MCP writes:
    /// ```
    /// sm-one
    /// <token>
    /// ```
    static func consumePreviewRequest() -> PreviewRequest? {
        let url = previewRequestURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        try? FileManager.default.removeItem(at: url)
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = lines.first,
              let address = CanvasAddress(rawValue: first)
        else { return nil }
        let token = lines.count > 1 ? lines[1] : UUID().uuidString
        return PreviewRequest(address: address, token: token)
    }
}

enum ReloadRequest: Equatable {
    case one(CanvasAddress)
    case all
}

struct PreviewRequest: Equatable {
    let address: CanvasAddress
    let token: String
}
