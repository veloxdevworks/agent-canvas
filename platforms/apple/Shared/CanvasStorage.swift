import Foundation
import WidgetKit
#if canImport(Darwin)
import Darwin
#endif

/// Reads/writes canvas JSON under the platform storage root.
/// - macOS: `~/.velox/canvas` (MCP + host + widgets via temporary-exception)
/// - iOS: App Group `group.com.velox.agentcanvas/canvas`
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

    /// Platform data root (`…/canvas`).
    static var applicationSupportRoot: URL {
        CanvasStorageRoot.root
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

    /// lastRender is per (definition, family) so small and large do not overwrite.
    static func lastRenderURL(for address: CanvasAddress, size: CanvasSize) -> URL {
        applicationSupportCanvases.appendingPathComponent("\(address.rawValue).\(size.rawValue).render.json")
    }

    static func previewPNGURL(for address: CanvasAddress, size: CanvasSize) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).\(size.rawValue).png")
    }

    static func previewTokenURL(for address: CanvasAddress, size: CanvasSize) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).\(size.rawValue).token")
    }

    static func previewMetaURL(for address: CanvasAddress, size: CanvasSize) -> URL {
        previewsRoot.appendingPathComponent("\(address.rawValue).\(size.rawValue).meta.json")
    }

    static var previewRequestURL: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.previewRequestFileName)
    }

    static var placedFamiliesURL: URL {
        applicationSupportRoot.appendingPathComponent(AgentCanvasConstants.placedFamiliesFileName)
    }

    /// Phase B: widget reports what it actually showed after clipping.
    static func writeLastRender(_ report: LastRenderReport, address: CanvasAddress, size: CanvasSize) {
        ensureDirectories()
        do {
            let data = try encoder.encode(report)
            try data.write(to: lastRenderURL(for: address, size: size), options: .atomic)
        } catch {
            NSLog("AgentCanvas: writeLastRender failed: \(error)")
        }
    }

    static func loadLastRender(address: CanvasAddress, size: CanvasSize) -> LastRenderReport? {
        let url = lastRenderURL(for: address, size: size)
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
        if let url = resolveReadURL(for: address), let doc = decode(from: url) {
            return doc
        }
        return .empty
    }

    /// Canonical `one.json` if present; else legacy aliases.
    /// Prefer a non-empty `md-*`, else the first non-empty in sm → md → lg → xl.
    /// Conflicting alias files are never merged.
    static func resolveReadURL(for address: CanvasAddress) -> URL? {
        let canonical = applicationSupportURL(for: address)
        if FileManager.default.fileExists(atPath: canonical.path) {
            return canonical
        }
        var mdNonempty: URL?
        var firstNonempty: URL?
        for name in address.legacyFileNames {
            let url = applicationSupportCanvases.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let nonempty = decode(from: url).map { !$0.isEmptyContent } ?? false
            if nonempty && firstNonempty == nil {
                firstNonempty = url
            }
            if nonempty && name.hasPrefix("md-") {
                mdNonempty = url
            }
        }
        return mdNonempty ?? firstNonempty
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
        PlacedFamiliesStore.snapshotFromWidgetCenter()
    }

    static func reload(address: CanvasAddress) {
        WidgetCenter.shared.reloadTimelines(ofKind: address.widgetKind)
        PlacedFamiliesStore.snapshotFromWidgetCenter()
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

    /// MCP writes definition id on first line (e.g. `one`). Legacy `md-one` still parses.
    /// Returns `.all` when a reload was requested without a parsable canvas id.
    static func consumeReloadRequest() -> ReloadRequest? {
        let url = reloadRequestURL
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        try? FileManager.default.removeItem(at: url)
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        let key = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = CanvasAddress.parse(key) {
            return .one(address)
        }
        for token in key.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            if let address = CanvasAddress.parse(String(token)) {
                return .one(address)
            }
        }
        // Timestamp-only or empty body — reload everything.
        return .all
    }

    /// MCP writes:
    /// ```
    /// one
    /// <token>
    /// md
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
              let parsed = CanvasAddress.parseFull(first)
        else { return nil }
        let token = lines.count > 1 ? lines[1] : UUID().uuidString
        let size: CanvasSize = {
            if lines.count > 2, let explicit = CanvasSize.parse(lines[2]) {
                return explicit
            }
            if let alias = parsed.aliasSize {
                return alias
            }
            return PlacedFamiliesStore.budgetSize(for: parsed.address)
        }()
        return PreviewRequest(address: parsed.address, size: size, token: token)
    }
}

/// WidgetCenter → App Group / `~/.velox/canvas` snapshot so MCP can budget by placed family.
enum PlacedFamiliesStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    struct Snapshot: Codable {
        var version: Int
        var updatedAt: Date?
        var canvases: [String: [String]]
    }

    static func load() -> Snapshot {
        guard let data = try? Data(contentsOf: CanvasStorage.placedFamiliesURL),
              let snap = try? decoder.decode(Snapshot.self, from: data)
        else {
            return Snapshot(version: 1, updatedAt: nil, canvases: [:])
        }
        return snap
    }

    static func families(for address: CanvasAddress) -> [CanvasSize] {
        let raw = load().canvases[address.rawValue] ?? []
        let sizes = raw.compactMap(CanvasSize.parse)
        return CanvasSize.allCases.filter { sizes.contains($0) }
    }

    /// Placed family if unique; else medium (documented default).
    static func budgetSize(for address: CanvasAddress) -> CanvasSize {
        let placed = families(for: address)
        if placed.count == 1 { return placed[0] }
        if placed.contains(.md) { return .md }
        if let first = placed.first { return first }
        return .defaultBudget
    }

    static func snapshotFromWidgetCenter() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case .success(let infos):
                var map: [String: [String]] = [:]
                for info in infos {
                    guard let address = CanvasAddress.from(widgetKind: info.kind),
                          let size = CanvasSize(widgetFamily: info.family)
                    else { continue }
                    var list = map[address.rawValue] ?? []
                    if !list.contains(size.rawValue) {
                        list.append(size.rawValue)
                    }
                    map[address.rawValue] = list
                }
                write(Snapshot(version: 1, updatedAt: Date(), canvases: map))
            case .failure(let error):
                NSLog("AgentCanvas: WidgetCenter configurations failed: \(error)")
            }
        }
    }

    private static func write(_ snap: Snapshot) {
        CanvasStorage.ensureDirectories()
        do {
            let data = try encoder.encode(snap)
            try data.write(to: CanvasStorage.placedFamiliesURL, options: .atomic)
        } catch {
            NSLog("AgentCanvas: write placed-families failed: \(error)")
        }
    }
}

/// Resolves the on-disk canvas root for the current platform.
enum CanvasStorageRoot {
    static var root: URL {
        #if os(iOS)
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AgentCanvasConstants.appGroupId
        ) {
            return container
                .appendingPathComponent(AgentCanvasConstants.canvasDirName, isDirectory: true)
        }
        // Simulator / misconfigured entitlements fallback.
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AgentCanvasConstants.canvasDirName, isDirectory: true)
        #else
        return realUserHome
            .appendingPathComponent(AgentCanvasConstants.veloxDirName, isDirectory: true)
            .appendingPathComponent(AgentCanvasConstants.canvasDirName, isDirectory: true)
        #endif
    }

    #if os(macOS)
    /// Real login home — not the App Sandbox container home.
    static var realUserHome: URL {
        #if canImport(Darwin)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }
    #endif
}

enum ReloadRequest: Equatable {
    case one(CanvasAddress)
    case all
}

struct PreviewRequest: Equatable {
    let address: CanvasAddress
    let size: CanvasSize
    let token: String
}
