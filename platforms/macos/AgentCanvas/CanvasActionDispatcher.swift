import AppKit
import Foundation

/// Resolves pointer-style action URLs against on-disk canvas JSON and executes them.
@MainActor
enum CanvasActionDispatcher {
    enum Outcome {
        /// Open / focus the detail window for this canvas id.
        case expand(canvasId: String)
        /// Open the main window and How to Use guide.
        case showHowTo
        /// Open Cloud UI with a subscribe slot picker for this slug.
        case subscribe(slug: String)
        /// URL / file / noop handled; do not open a host window.
        case handledExternally
    }

    @discardableResult
    static func handleOpenURL(_ url: URL) -> Outcome {
        guard let target = CanvasActionURL.parse(url) else {
            return .handledExternally
        }
        return execute(target: target)
    }

    @discardableResult
    static func execute(target: CanvasActionURL.Target) -> Outcome {
        switch target {
        case .howTo:
            return .showHowTo

        case let .subscribe(slug):
            return .subscribe(slug: slug)

        case let .document(id):
            guard let address = CanvasAddress(rawValue: id) else {
                status("Unknown canvas id \(id)")
                return .handledExternally
            }
            let doc = CanvasStorage.load(address: address)
            let action = doc.resolvedOnOpen
            return perform(action, canvasId: id, context: "onOpen")

        case let .item(id, section, item, version):
            guard let address = CanvasAddress(rawValue: id) else {
                status("Unknown canvas id \(id)")
                return .handledExternally
            }
            let doc = CanvasStorage.load(address: address)
            // Prefer glance sections; fall back to detail sections for detail-window links.
            let sections = doc.sections
            guard section < sections.count,
                  case let .list(_, items, _) = sections[section],
                  item < items.count
            else {
                status("Stale widget tap — opening expand for \(id)")
                return .expand(canvasId: id)
            }
            let listItem = items[item]
            let expected = CanvasActionURL.versionDigest(for: listItem.primary)
            guard version.isEmpty || version == expected else {
                status("Stale list row — opening expand for \(id)")
                return .expand(canvasId: id)
            }
            guard let action = listItem.action else {
                return .expand(canvasId: id)
            }
            return perform(action, canvasId: id, context: "sections[\(section)].items[\(item)].action")
        }
    }

    /// Execute a concrete action already resolved from a document (detail window rows).
    @discardableResult
    static func perform(
        _ action: CanvasAction,
        canvasId: String,
        context: String
    ) -> Outcome {
        do {
            try action.validate(context: context)
        } catch {
            status(error.localizedDescription)
            return .handledExternally
        }

        switch action {
        case .expand:
            return .expand(canvasId: canvasId)
        case .noop:
            status("No action for \(canvasId)")
            return .handledExternally
        case let .url(raw):
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                status("Invalid URL for \(canvasId)")
                return .handledExternally
            }
            NSWorkspace.shared.open(url)
            return .handledExternally
        case let .file(path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (trimmed as NSString).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expanded)
            // Reveal only — never launch.
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return .handledExternally
        }
    }

    private static func status(_ line: String) {
        HostRuntime.watcher?.setStatusLine(line)
        NSLog("AgentCanvas action: \(line)")
    }
}
