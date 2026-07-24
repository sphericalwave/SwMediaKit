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

    @State private var paused = false
    @State private var pausedIndex = 0

    public init(items: [Item], interval: TimeInterval = 4.0) {
        self.items = items
        self.interval = interval
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if !items.isEmpty {
                    if paused {
                        thumbnail(for: items[pausedIndex % items.count], size: geo.size.width)
                    } else {
                        TimelineView(.periodic(from: .now, by: interval)) { timeline in
                            let idx = Int(timeline.date.timeIntervalSinceReferenceDate / interval) % items.count
                            thumbnail(for: items[idx], size: geo.size.width)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !items.isEmpty {
                    pauseButton
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func thumbnail(for item: Item, size: CGFloat) -> some View {
        PosterThumbnail(assetName: item.assetNames.first, assetNames: item.assetNames,
                        photos: item.photos, size: size)
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
