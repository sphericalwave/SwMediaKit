//
//  PosterThumbnail.swift
//  SwMediaKit
//
//  Small square thumbnail: a bundle-image flipbook, a decoded custom-photo
//  flipbook, or a single image, with an SF Symbol fallback. Custom photos are
//  decoded downsampled off the main actor for the tiny display size and kept
//  in the shared `ThumbnailCache`, keyed by the photo bytes — so a replaced
//  photo always reloads, and a row scrolling back in draws from cache.
//

import SwiftUI

public struct PosterThumbnail: View {
    let assetName: String?
    var assetNames: [String]
    var photoData: Data?
    var photos: [Data]
    var size: CGFloat
    var contentMode: ContentMode
    var borderColor: Color?

    /// Decoded frames and the photo bytes they were decoded from.
    @State private var loaded: (sources: [Data], images: [PlatformImage]) = ([], [])

    public init(assetName: String? = nil, assetNames: [String] = [],
                photoData: Data? = nil, photos: [Data] = [], size: CGFloat = 48,
                contentMode: ContentMode = .fit, borderColor: Color? = nil) {
        self.assetName = assetName
        self.assetNames = assetNames
        self.photoData = photoData
        self.photos = photos
        self.size = size
        self.contentMode = contentMode
        self.borderColor = borderColor
    }

    /// Corner radius of the image itself.
    private let cornerRadius: CGFloat = 4
    /// Corner radius of the border ring and the white plate behind the gap
    /// (slightly larger than `cornerRadius` so the two nest cleanly).
    private let outerCornerRadius: CGFloat = 6
    /// Gap between the image's edge and the border stroke — keeps the
    /// stroke from overlapping the image's own pixels.
    private let borderGap: CGFloat = 3
    private let borderLineWidth: CGFloat = 2

    private var bundleNames: [String] {
        assetNames.isEmpty ? (assetName.map { [$0] } ?? []) : assetNames
    }

    /// Custom photos to show: the flipbook if given, else the single photo.
    private var photoSources: [Data] {
        photos.isEmpty ? (photoData.map { [$0] } ?? []) : photos
    }

    private var maxPixel: CGFloat { size * 3 }

    /// Frames for the current photos: the last load if it matches, else a
    /// synchronous cache hit (no placeholder flash), else none yet.
    private var photoImages: [PlatformImage] {
        let sources = photoSources
        if loaded.sources == sources { return loaded.images }
        let hits = sources.compactMap { ThumbnailCache.image(for: $0, maxPixel: maxPixel) }
        return hits.count == sources.count ? hits : []
    }

    private var effectiveBorderGap: CGFloat {
        borderColor == nil ? 0 : borderGap
    }

    @ViewBuilder
    private var outerBackground: some View {
        if borderColor != nil {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .fill(Color.white)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let borderColor {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: borderLineWidth)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if bundleNames.count > 1 {
            TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                let idx = Int(tl.date.timeIntervalSinceReferenceDate) % bundleNames.count
                Image(bundleNames[idx]).resizable().aspectRatio(contentMode: contentMode)
            }
        } else if let n = bundleNames.first {
            Image(n).resizable().aspectRatio(contentMode: contentMode)
        } else {
            photoContent(photoImages)
        }
    }

    @ViewBuilder
    private func photoContent(_ images: [PlatformImage]) -> some View {
        if images.count > 1 {
            TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                let idx = Int(tl.date.timeIntervalSinceReferenceDate) % images.count
                Image(platformImage: images[idx]).resizable().aspectRatio(contentMode: contentMode)
            }
        } else if let img = images.first {
            Image(platformImage: img).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Image(systemName: "figure.yoga")
                .resizable().scaledToFit()
                .padding(8)
                .foregroundStyle(.secondary)
        }
    }

    public var body: some View {
        imageContent
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .padding(effectiveBorderGap)
            .background(outerBackground)
            .overlay(borderOverlay)
            .task(id: photoSources) {
                let sources = photoSources
                guard bundleNames.isEmpty, !sources.isEmpty,
                      loaded.sources != sources else { return }
                let images = await Self.load(sources, maxPixel: maxPixel)
                guard !Task.isCancelled else { return }
                loaded = (sources, images)
            }
    }

    /// Off the main actor (nonisolated async); cancelled with the `.task`
    /// when the row disappears, skipping any frames not yet decoded.
    private nonisolated static func load(_ sources: [Data], maxPixel: CGFloat) async -> [PlatformImage] {
        var images: [PlatformImage] = []
        for data in sources {
            if Task.isCancelled { return [] }
            if let hit = ThumbnailCache.image(for: data, maxPixel: maxPixel) {
                images.append(hit)
            } else if let img = PlatformImage.downsampled(data: data, maxPixel: maxPixel) {
                ThumbnailCache.insert(img, for: data, maxPixel: maxPixel)
                images.append(img)
            }
        }
        return images
    }
}

#if DEBUG
#Preview("Single photo") {
    PosterThumbnail(photoData: PreviewSample.one, size: 88)
}

#Preview("Flipbook + border") {
    PosterThumbnail(photos: PreviewSample.many, size: 88, borderColor: .blue)
}

#Preview("Fallback") {
    PosterThumbnail(size: 88)
}
#endif
