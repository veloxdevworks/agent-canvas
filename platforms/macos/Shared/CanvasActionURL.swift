import Foundation
import CryptoKit

/// Pointer-style deep links for canvas actions.
///
/// Widget emits `agentcanvas://action?…`; host re-reads JSON and executes.
/// Legacy `agentcanvas://detail?id=` remains an alias for expand.
enum CanvasActionURL {
    static let scheme = "agentcanvas"
    static let actionHost = "action"
    static let detailHost = "detail"

    enum Target: Equatable {
        /// Document `onOpen` (or legacy detail expand).
        case document(id: String)
        /// List item action at document section/item indices.
        case item(id: String, section: Int, item: Int, version: String)
    }

    // MARK: - Build

    static func documentURL(canvasId: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = actionHost
        components.queryItems = [
            URLQueryItem(name: "id", value: canvasId),
        ]
        return components.url!
    }

    static func itemURL(canvasId: String, section: Int, item: ListItem, itemIndex: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = actionHost
        components.queryItems = [
            URLQueryItem(name: "id", value: canvasId),
            URLQueryItem(name: "section", value: String(section)),
            URLQueryItem(name: "item", value: String(itemIndex)),
            URLQueryItem(name: "v", value: versionDigest(for: item.primary)),
        ]
        return components.url!
    }

    /// Short digest of primary text for stale-timeline detection.
    static func versionDigest(for primary: String) -> String {
        let data = Data(primary.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Parse

    static func parse(_ url: URL) -> Target? {
        guard url.scheme == scheme else { return nil }

        if url.host == detailHost {
            guard let id = queryValue(url, name: "id"), !id.isEmpty else { return nil }
            return .document(id: id)
        }

        guard url.host == actionHost else { return nil }
        guard let id = queryValue(url, name: "id"), !id.isEmpty else { return nil }

        let sectionStr = queryValue(url, name: "section")
        let itemStr = queryValue(url, name: "item")
        if sectionStr == nil && itemStr == nil {
            return .document(id: id)
        }
        guard
            let sectionStr,
            let itemStr,
            let section = Int(sectionStr),
            let item = Int(itemStr),
            section >= 0,
            item >= 0
        else {
            return nil
        }
        let v = queryValue(url, name: "v") ?? ""
        return .item(id: id, section: section, item: item, version: v)
    }

    private static func queryValue(_ url: URL, name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

/// How list rows should expose actions in a given surface.
enum CanvasActionInteractionMode: Equatable {
    /// md/lg/xl widget: wrap actionable rows in `Link`.
    case widgetLink
    /// Host detail window: buttons that call the dispatcher.
    case hostButton
    /// Settings preview / PNG renderer: no interaction.
    case inert
}
