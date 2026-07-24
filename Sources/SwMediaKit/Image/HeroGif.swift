//
//  HeroGif.swift
//  SwMediaKit
//
//  Full-width, square "cover" flipbook: cycles through a list of items
//  (each its own bundle-image/custom-photo set, same sourcing as
//  `PosterThumbnail`) at a fixed interval, with a pause/play toggle.
//  Pausing freezes which item is shown; an item with more than one image
//  of its own keeps flipping through those via `PosterThumbnail`'s own
//  internal timer.
//

import SwiftUI

public struct HeroGif: View {
    public struct Item {
        public let assetNames: [String]
        public let photos: [Data]

        public init(assetNames: [String] = [], photos: [Data] = []) {
            self.assetNames = assetNames
            self.photos = photos
        }
    }

    let items: [Item]
    var interval: TimeInterval
    var borderColor: Color
    var showPauseButton: Bool

    @State private var paused = false
    @State private var pausedIndex = 0

    public init(items: [Item], interval: TimeInterval = 4.0, borderColor: Color = .swBlue,
                showPauseButton: Bool = true) {
        self.items = items
        self.interval = interval
        self.borderColor = borderColor
        self.showPauseButton = showPauseButton
    }

    private let cornerRadius: CGFloat = 8
    /// Gap between the image's edge and the border stroke — keeps the
    /// stroke from overlapping the image's own pixels. Shrinks the inner
    /// image rather than padding the outer frame, so `HeroGif` still
    /// reports exactly the size its container gave it.
    private let borderGap: CGFloat = 4
    private let borderLineWidth: CGFloat = 3

    public var body: some View {
        GeometryReader { geo in
            let innerSize = max(geo.size.width - borderGap * 2, 0)
            content(size: innerSize)
                .frame(width: geo.size.width, height: geo.size.width)
                .background(outerBackground)
                .overlay(border)
                .overlay(alignment: .bottomTrailing) { pauseOverlay }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func content(size: CGFloat) -> some View {
        if !items.isEmpty {
            if paused {
                thumbnail(for: items[pausedIndex % items.count], size: size)
            } else {
                TimelineView(.periodic(from: .now, by: interval)) { timeline in
                    let idx = Int(timeline.date.timeIntervalSinceReferenceDate / interval) % items.count
                    thumbnail(for: items[idx], size: size)
                }
            }
        }
    }

    private func thumbnail(for item: Item, size: CGFloat) -> some View {
        PosterThumbnail(assetName: item.assetNames.first, assetNames: item.assetNames,
                        photos: item.photos, size: size, contentMode: .fit)
    }

    private var outerBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: borderLineWidth)
    }

    @ViewBuilder
    private var pauseOverlay: some View {
        if !items.isEmpty && showPauseButton {
            pauseButton
        }
    }

    private var pauseButton: some View {
        Button {
            if !paused {
                pausedIndex = Int(Date().timeIntervalSinceReferenceDate / interval) % items.count
            }
            paused.toggle()
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}

public extension Color {
    /// SphericalWave brand blue — `HeroGif`'s default border color.
    static let swBlue = Color(red: 0/255, green: 122/255, blue: 255/255)
}
