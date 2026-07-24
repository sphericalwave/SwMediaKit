//
//  PosterThumbnail.swift
//  SwMediaKit
//
//  Small square thumbnail: a bundle-image flipbook, a decoded custom-photo
//  flipbook, or a single image, with an SF Symbol fallback. Custom photos are
//  decoded downsampled off the main actor for the tiny display size.
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

    @State private var cachedPhotos: [PlatformImage] = []
    @State private var cachedPhoto: PlatformImage? = nil

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

    private var bundleNames: [String] {
        assetNames.isEmpty ? (assetName.map { [$0] } ?? []) : assetNames
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let borderColor {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(borderColor, lineWidth: 2)
        }
    }

    public var body: some View {
        Group {
            if bundleNames.count > 1 {
                TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                    let idx = Int(tl.date.timeIntervalSinceReferenceDate) % bundleNames.count
                    Image(bundleNames[idx]).resizable().aspectRatio(contentMode: contentMode)
                }
            } else if let n = bundleNames.first {
                Image(n).resizable().aspectRatio(contentMode: contentMode)
            } else if cachedPhotos.count > 1 {
                TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                    let idx = Int(tl.date.timeIntervalSinceReferenceDate) % cachedPhotos.count
                    Image(platformImage: cachedPhotos[idx]).resizable().aspectRatio(contentMode: contentMode)
                }
            } else if let img = cachedPhotos.first {
                Image(platformImage: img).resizable().aspectRatio(contentMode: contentMode)
            } else if let img = cachedPhoto {
                Image(platformImage: img).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "figure.yoga")
                    .resizable().scaledToFit()
                    .padding(8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(borderOverlay)
        .task(id: photos.count) {
            guard bundleNames.isEmpty else { return }
            let data = photos
            let maxPixel = size * 3
            cachedPhotos = await Task.detached(priority: .userInitiated) {
                data.compactMap { PlatformImage.downsampled(data: $0, maxPixel: maxPixel) }
            }.value
        }
        .task(id: photoData?.count) {
            guard bundleNames.isEmpty, photos.isEmpty else { return }
            let data = photoData
            let maxPixel = size * 3
            cachedPhoto = await Task.detached(priority: .userInitiated) {
                data.flatMap { PlatformImage.downsampled(data: $0, maxPixel: maxPixel) }
            }.value
        }
    }
}
