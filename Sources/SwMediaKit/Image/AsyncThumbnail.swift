//
//  AsyncThumbnail.swift
//  SwMediaKit
//
//  List-row thumbnail for stored image `Data` or an image URL. Decodes
//  downsampled (ImageIO, largest edge ~`maxPixel` px) off the main actor,
//  memoises the result in a shared in-memory cache, and shows `placeholder`
//  until the image is ready. The load runs in `.task`, so it is cancelled when
//  the row disappears; a cancelled load that hasn't started decoding is
//  skipped entirely.
//
//  The view only draws the image `resizable()` with `contentMode` — callers
//  own the frame, clip shape and any border, so it fits any row shape.
//
//      AsyncThumbnail(data: item.imageData, id: item.uuid, maxPixel: 44 * 3)
//          .frame(width: 44, height: 44)
//          .clipShape(RoundedRectangle(cornerRadius: 6))
//

import SwiftUI
import ImageIO

public struct AsyncThumbnail<Placeholder: View>: View {
    private enum Source {
        case data(Data)
        case url(URL)
    }

    private let source: Source?
    /// Cache key: caller id + target size (+ byte count for data, so a
    /// replacement image under the same id never shows the stale one).
    private let key: String
    private let maxPixel: CGFloat
    private let contentMode: ContentMode
    private let placeholder: Placeholder

    @State private var loaded: (key: String, image: PlatformImage)?

    /// - Parameters:
    ///   - data: Encoded image bytes (JPEG/HEIC/PNG/GIF…). `nil` shows the placeholder.
    ///   - id: Stable identity of the image's owner (model UUID, objectID string…).
    ///   - maxPixel: Largest edge to decode, in pixels — typically point size × 3.
    public init(data: Data?, id: some Hashable, maxPixel: CGFloat,
                contentMode: ContentMode = .fill,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.source = data.map(Source.data)
        self.key = "\(id)-\(Int(maxPixel))-\(data?.count ?? 0)"
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    /// - Parameters:
    ///   - url: A file URL (read via ImageIO) or a remote URL (fetched, then
    ///     downsampled). `nil` shows the placeholder. The URL is the cache id.
    ///   - maxPixel: Largest edge to decode, in pixels — typically point size × 3.
    public init(url: URL?, maxPixel: CGFloat,
                contentMode: ContentMode = .fill,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.source = url.map(Source.url)
        self.key = "\(url?.absoluteString ?? "")-\(Int(maxPixel))"
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    /// The loaded image if it is for the current key, else a cache hit — so a
    /// row scrolling back in draws immediately without a placeholder flash.
    private var image: PlatformImage? {
        if let loaded, loaded.key == key { return loaded.image }
        return source == nil ? nil : ThumbnailCache.image(for: key)
    }

    public var body: some View {
        Group {
            if let image {
                Image(platformImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: key) {
            guard let source, image == nil else { return }
            guard let decoded = await Self.load(source, maxPixel: maxPixel),
                  !Task.isCancelled else { return }
            ThumbnailCache.insert(decoded, for: key)
            loaded = (key, decoded)
        }
    }

    /// Runs off the main actor (nonisolated async). Inherits the `.task`'s
    /// cancellation: bails before the decode if the row has already gone.
    private nonisolated static func load(_ source: Source, maxPixel: CGFloat) async -> PlatformImage? {
        switch source {
        case .data(let data):
            guard !Task.isCancelled else { return nil }
            return PlatformImage.downsampled(data: data, maxPixel: maxPixel)
        case .url(let url) where url.isFileURL:
            guard !Task.isCancelled else { return nil }
            return downsampled(fileURL: url, maxPixel: maxPixel)
        case .url(let url):
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled else { return nil }
            return PlatformImage.downsampled(data: data, maxPixel: maxPixel)
        }
    }

    /// Reads a file through ImageIO without loading it all into `Data` first.
    private nonisolated static func downsampled(fileURL: URL, maxPixel: CGFloat) -> PlatformImage? {
        guard let src = CGImageSourceCreateWithURL(
            fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return PlatformImage(decodedCGImage: cg)
    }
}

public extension AsyncThumbnail where Placeholder == Color {
    /// Neutral grey fill until the image is ready.
    init(data: Data?, id: some Hashable, maxPixel: CGFloat, contentMode: ContentMode = .fill) {
        self.init(data: data, id: id, maxPixel: maxPixel, contentMode: contentMode) {
            Color.gray.opacity(0.15)
        }
    }

    init(url: URL?, maxPixel: CGFloat, contentMode: ContentMode = .fill) {
        self.init(url: url, maxPixel: maxPixel, contentMode: contentMode) {
            Color.gray.opacity(0.15)
        }
    }
}

/// Process-wide decoded-thumbnail cache shared by every `AsyncThumbnail`.
/// `NSCache` is thread-safe and evicts under memory pressure; cost is the
/// decoded bitmap size, capped at ~64 MB.
enum ThumbnailCache {
    private static let cache: NSCache<NSString, PlatformImage> = {
        let c = NSCache<NSString, PlatformImage>()
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    static func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    static func insert(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.decodedByteCost)
    }
}

private extension PlatformImage {
    /// Bitmap bytes (w × h × 4) of the backing CGImage, for cache costing.
    var decodedByteCost: Int {
        guard let cg = backingCGImage else { return 0 }
        return cg.width * cg.height * 4
    }
}

#if DEBUG
#Preview("Data, cached") {
    VStack(spacing: 12) {
        ForEach(Array(PreviewSample.many.enumerated()), id: \.offset) { i, data in
            AsyncThumbnail(data: data, id: i, maxPixel: 60 * 3)
                .frame(width: 60, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
    .padding()
}

#Preview("Placeholder") {
    AsyncThumbnail(data: nil, id: 0, maxPixel: 132) {
        Image(systemName: "photo").foregroundStyle(.secondary)
    }
    .frame(width: 44, height: 44)
}
#endif
