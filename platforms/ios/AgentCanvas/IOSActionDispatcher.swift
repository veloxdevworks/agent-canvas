import Foundation
import UIKit

/// Resolves pointer-style action URLs against on-disk canvas JSON and executes them.
@MainActor
enum IOSActionDispatcher {
    enum Outcome {
        case expand(canvasId: String)
        case showHowTo
        case subscribe(slug: String)
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
                return .handledExternally
            }
            let doc = CanvasStorage.load(address: address)
            return perform(doc.resolvedOnOpen, canvasId: id)

        case let .item(id, section, item, version):
            guard let address = CanvasAddress(rawValue: id) else {
                return .handledExternally
            }
            let doc = CanvasStorage.load(address: address)
            let sections = doc.sections
            guard section < sections.count,
                  case let .list(_, items, _) = sections[section],
                  item < items.count
            else {
                return .expand(canvasId: id)
            }
            let listItem = items[item]
            let expected = CanvasActionURL.versionDigest(for: listItem.primary)
            guard version.isEmpty || version == expected else {
                return .expand(canvasId: id)
            }
            guard let action = listItem.action else {
                return .expand(canvasId: id)
            }
            return perform(action, canvasId: id)
        }
    }

    @discardableResult
    static func perform(_ action: CanvasAction, canvasId: String) -> Outcome {
        do {
            try action.validate(context: canvasId)
        } catch {
            NSLog("AgentCanvas iOS action: \(error.localizedDescription)")
            return .handledExternally
        }

        switch action {
        case .expand:
            return .expand(canvasId: canvasId)
        case .noop:
            return .handledExternally
        case let .url(raw):
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return .handledExternally
            }
            UIApplication.shared.open(url)
            return .handledExternally
        case let .file:
            // Files aren't useful on iOS phone UI — expand instead.
            return .expand(canvasId: canvasId)
        }
    }
}
