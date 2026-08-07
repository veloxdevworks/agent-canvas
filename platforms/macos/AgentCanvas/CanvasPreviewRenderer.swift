import AppKit
import Foundation
import SwiftUI
import CoreGraphics

/// Renders the same `CanvasView` the widget uses into a PNG for MCP agents.
@MainActor
enum CanvasPreviewRenderer {
    struct Result: Codable {
        var canvas: String
        var token: String
        var ok: Bool
        var path: String?
        var width: Int?
        var height: Int?
        var scale: Double?
        var truncated: Bool?
        var droppedTypes: [String]?
        var listItemsShown: Int?
        var listItemsTotal: Int?
        var error: String?
        var updatedAt: Date
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Render + write `previews/{id}.png`, `{id}.token`, `{id}.meta.json`.
    @discardableResult
    static func render(request: PreviewRequest) -> Result {
        CanvasStorage.ensureDirectories()
        let address = request.address
        let tile = ContentClip.defaultTileSize(for: address.size)
        let doc = CanvasStorage.load(address: address)

        let hasTitle = (doc.title?.isEmpty == false) && address.size != .sm
        let hasTimestamp = doc.updatedAt != nil
        let live = !doc.isEmptyContent
        // Prefer fitting everything first; only reserve overflow chrome when needed.
        var budget = ContentClip.contentBudget(
            displaySize: tile,
            size: address.size,
            hasTitle: hasTitle && live,
            hasTimestamp: hasTimestamp && live,
            reserveOverflowLine: false
        )
        var clip = ContentClip.apply(document: doc, size: address.size, maxHeight: budget)
        if clip.truncated {
            budget = ContentClip.contentBudget(
                displaySize: tile,
                size: address.size,
                hasTitle: hasTitle && live,
                hasTimestamp: hasTimestamp && live,
                reserveOverflowLine: true
            )
            clip = ContentClip.apply(document: doc, size: address.size, maxHeight: budget)
        }

        let entry = CanvasEntry(
            date: Date(),
            address: address,
            document: doc,
            isPlaceholder: doc.isEmptyContent,
            clip: clip,
            displaySize: tile
        )

        let view = CanvasView(entry: entry, isPreview: true)
            .frame(width: tile.width, height: tile.height)
            // Neutral desk so the squircle reads clearly in agent UIs.
            .padding(16)
            .background(Color(red: 0.22, green: 0.23, blue: 0.25))
            // Keep MCP PNGs dark so agent screenshots stay consistent across hosts.
            .environment(\.colorScheme, .dark)

        let scale: CGFloat = 2.0
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(
            width: tile.width + 32,
            height: tile.height + 32
        )

        guard let cgImage = renderer.cgImage else {
            let fail = Result(
                canvas: address.rawValue,
                token: request.token,
                ok: false,
                path: nil,
                width: nil,
                height: nil,
                scale: Double(scale),
                truncated: clip.truncated,
                droppedTypes: clip.droppedTypes,
                listItemsShown: clip.listItemsShown,
                listItemsTotal: clip.listItemsTotal,
                error: "ImageRenderer returned no image (is the host UI process alive?)",
                updatedAt: Date()
            )
            writeMeta(fail, address: address)
            writeToken(request.token, address: address)
            return fail
        }

        let pngURL = CanvasStorage.previewPNGURL(for: address)
        do {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw PreviewError.encodeFailed
            }
            let tmp = pngURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: pngURL.path) {
                try FileManager.default.removeItem(at: pngURL)
            }
            try FileManager.default.moveItem(at: tmp, to: pngURL)
        } catch {
            let fail = Result(
                canvas: address.rawValue,
                token: request.token,
                ok: false,
                path: nil,
                width: cgImage.width,
                height: cgImage.height,
                scale: Double(scale),
                truncated: clip.truncated,
                droppedTypes: clip.droppedTypes,
                listItemsShown: clip.listItemsShown,
                listItemsTotal: clip.listItemsTotal,
                error: "write failed: \(error.localizedDescription)",
                updatedAt: Date()
            )
            writeMeta(fail, address: address)
            writeToken(request.token, address: address)
            return fail
        }

        // Mirror last-render metadata so get_canvas stays useful after preview-only flows.
        if !doc.isEmptyContent {
            let report = LastRenderReport(
                canvas: address.rawValue,
                size: address.size.rawValue,
                truncated: clip.truncated,
                shownSectionCount: clip.shown.count,
                droppedSectionCount: clip.droppedTypes.count,
                droppedTypes: clip.droppedTypes,
                listItemsShown: clip.listItemsShown,
                listItemsTotal: clip.listItemsTotal,
                updatedAt: Date()
            )
            CanvasStorage.writeLastRender(report, address: address)
        }

        let ok = Result(
            canvas: address.rawValue,
            token: request.token,
            ok: true,
            path: pngURL.path,
            width: cgImage.width,
            height: cgImage.height,
            scale: Double(scale),
            truncated: clip.truncated,
            droppedTypes: clip.droppedTypes,
            listItemsShown: clip.listItemsShown,
            listItemsTotal: clip.listItemsTotal,
            error: nil,
            updatedAt: Date()
        )
        writeMeta(ok, address: address)
        writeToken(request.token, address: address)
        NSLog("AgentCanvas: preview \(address.rawValue) → \(pngURL.lastPathComponent) token=\(request.token.prefix(8))…")
        return ok
    }

    private static func writeToken(_ token: String, address: CanvasAddress) {
        let url = CanvasStorage.previewTokenURL(for: address)
        try? token.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func writeMeta(_ result: Result, address: CanvasAddress) {
        let url = CanvasStorage.previewMetaURL(for: address)
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private enum PreviewError: Error {
        case encodeFailed
    }
}
