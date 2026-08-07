import Foundation
import AppKit
import ImageIO
import CoreGraphics
import SwiftUI

/// Resolve and downsample canvas images (`asset:` under `~/.velox/canvas/assets/`,
/// or legacy inline `data:image/…;base64,…`).
/// WidgetKit-safe: never loads full-size bitmaps into memory.
enum CanvasImageLoader {
    private static let cache = NSCache<NSString, NSImage>()

    /// Load a downsampled image for the given target pixel size (max edge).
    static func load(source: String, maxPixelSize: CGFloat) -> NSImage? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cache key for data: must not use the full base64 string (huge / collision-prone).
        let key: NSString = {
            if trimmed.hasPrefix("data:") {
                return "data:\(trimmed.count):\(trimmed.hashValue)|\(Int(maxPixelSize))" as NSString
            }
            return "\(trimmed)|\(Int(maxPixelSize))" as NSString
        }()
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image: NSImage?
        if trimmed.hasPrefix("asset:") {
            guard let url = resolveAssetURL(source: trimmed) else { return nil }
            image = downsample(url: url, maxPixelSize: maxPixelSize)
        } else if trimmed.hasPrefix("data:") {
            guard let data = decodeDataURL(trimmed) else { return nil }
            image = downsample(data: data, maxPixelSize: maxPixelSize)
        } else {
            return nil
        }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    /// Resolve `asset:{sha}.{ext}` to a file URL under assetsRoot, with containment checks.
    static func resolveURL(source: String) -> URL? {
        resolveAssetURL(source: source)
    }

    private static func resolveAssetURL(source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("asset:") else { return nil }
        let rest = String(trimmed.dropFirst("asset:".count))
        guard let dot = rest.lastIndex(of: ".") else { return nil }
        let hash = String(rest[..<dot])
        let ext = String(rest[rest.index(after: dot)...])
        guard hash.count == 64,
              hash.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) })
        else {
            return nil
        }
        guard ext == "png" || ext == "jpg" else { return nil }
        if rest.contains("..") || rest.contains("/") || rest.contains("\\") {
            return nil
        }
        let url = CanvasStorage.assetsRoot.appendingPathComponent(rest, isDirectory: false)
        let assetsPath = CanvasStorage.assetsRoot.standardizedFileURL.path
        let resolved = url.standardizedFileURL.path
        guard resolved.hasPrefix(assetsPath + "/") || resolved == assetsPath else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: resolved) else { return nil }
        return url
    }

    private static func decodeDataURL(_ source: String) -> Data? {
        guard let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[source.startIndex..<comma]
        guard header.contains(";base64") else { return nil }
        let b64 = String(source[source.index(after: comma)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        if data.count > AgentCanvasConstants.maxImageBytes { return nil }
        // Magic-byte sniff (PNG / JPEG) — ignore declared mime.
        let isPng = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let isJpeg = data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
        guard isPng || isJpeg else { return nil }
        return data
    }

    private static func downsample(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        // Reject files ImageIO cannot fully decode (corrupt IDAT still often exposes IHDR).
        let status = CGImageSourceGetStatus(source)
        let statusAt = CGImageSourceGetStatusAtIndex(source, 0)
        guard status == .statusComplete || status == .statusIncomplete else { return nil }
        guard statusAt == .statusComplete || statusAt == .statusIncomplete else { return nil }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if width > 0, height > 0 {
            let pixels = width * height
            if pixels > Double(AgentCanvasConstants.maxImagePixels) {
                return nil
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded())),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // ImageIO can return a blank thumbnail for truncated PNGs — treat empty frames as failure.
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        // Corrupt PNG IDAT often still yields a solid black bitmap with statusComplete.
        // Reject that so cover tiles fall back instead of looking empty.
        if isSolidBlack(cgImage) {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// True when every sampled pixel is RGB(0,0,0). ImageIO does this for some broken PNGs.
    private static func isSolidBlack(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return true }
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var data = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Sparse sample — enough to catch ImageIO's all-black corrupt-PNG placeholder.
        let points: [(Int, Int)] = [
            (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
            (w / 2, h / 2), (w / 4, h / 4), (3 * w / 4, 3 * h / 4),
        ]
        for (x, y) in points {
            let i = (y * w + x) * bytesPerPixel
            if data[i] != 0 || data[i + 1] != 0 || data[i + 2] != 0 {
                return false
            }
        }
        return true
    }
}

/// SwiftUI helper for canvas images.
struct CanvasRemoteImage: View {
    let source: String
    let alt: String
    let maxPixelSize: CGFloat
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let nsImage = CanvasImageLoader.load(source: source, maxPixelSize: maxPixelSize) {
                // macOS dims desktop widgets when an app is focused (accented/glass mode).
                // Without this, ImageIO bitmaps become solid gray placeholders.
                imageView(nsImage)
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(alt)
            } else {
                Label(alt.isEmpty ? "Image unavailable" : alt, systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func imageView(_ nsImage: NSImage) -> some View {
        let base = Image(nsImage: nsImage).resizable()
        if #available(macOS 15.0, *) {
            // Accented/glass desktop mode (app focused): keep the bitmap visible but
            // desaturated so it blends with system widget chrome instead of a gray void.
            base.widgetAccentedRenderingMode(.desaturated)
        } else {
            base
        }
    }
}
