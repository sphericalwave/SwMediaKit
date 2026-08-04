//
//  AnimatedPoster.swift
//  SwMediaKit
//
//  Animated "flipbook" poster: cycles through bundle-named images or decoded
//  custom photos at ~3fps, with a pause toggle. Bundle images resolve from the
//  host app's `Bundle.main`. Custom photos are decoded downsampled off the main
//  actor so full-resolution picks never stall the UI when the view appears.
//

import SwiftUI

public struct AnimatedPoster: View {
    let bundleNames: [String]
    let photos: [Data]
    var maxHeight: CGFloat
    var cornerRadius: CGFloat

    @State private var paused = false
    @State private var pausedDate: Date = .now
    @State private var cachedCustomPhotos: [PlatformImage] = []
    @Environment(\.colorScheme) private var colorScheme

    public init(bundleNames: [String], photos: [Data],
                maxHeight: CGFloat = 220, cornerRadius: CGFloat = 12) {
        self.bundleNames = bundleNames
        self.photos = photos
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if !bundleNames.isEmpty {
                animatedBundleView(names: bundleNames)
            } else if !cachedCustomPhotos.isEmpty {
                animatedCustomView(images: cachedCustomPhotos)
            } else {
                Color.clear
            }
        }
        .task(id: photos.map(\.count)) {
            guard bundleNames.isEmpty else { return }
            let data = photos
            let maxPixel = maxHeight * 3   // retina cap for the display size
            cachedCustomPhotos = await Task.detached(priority: .userInitiated) {
                data.compactMap { PlatformImage.downsampled(data: $0, maxPixel: maxPixel) }
            }.value
        }
    }

    @ViewBuilder
    private func animatedBundleView(names: [String]) -> some View {
        Group {
            if paused {
                let idx = Int(pausedDate.timeIntervalSinceReferenceDate) % names.count
                Image(names[idx])
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                    let idx = Int(tl.date.timeIntervalSinceReferenceDate) % names.count
                    Image(names[idx])
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: maxHeight)
                }
            }
        }
        .modifier(PosterFrame(maxHeight: maxHeight, cornerRadius: cornerRadius,
                              colorScheme: colorScheme, showPause: true,
                              paused: $paused, onPause: { pausedDate = .now }))
    }

    @ViewBuilder
    private func animatedCustomView(images: [PlatformImage]) -> some View {
        Group {
            if paused || images.count == 1 {
                let idx = Int(pausedDate.timeIntervalSinceReferenceDate) % images.count
                Image(platformImage: images[idx])
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 0.333)) { tl in
                    let idx = Int(tl.date.timeIntervalSinceReferenceDate) % images.count
                    Image(platformImage: images[idx])
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: maxHeight)
                }
            }
        }
        .modifier(PosterFrame(maxHeight: maxHeight, cornerRadius: cornerRadius,
                              colorScheme: colorScheme, showPause: images.count > 1,
                              paused: $paused, onPause: { pausedDate = .now }))
    }
}

private struct PosterFrame: ViewModifier {
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    let showPause: Bool
    @Binding var paused: Bool
    var onPause: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .topTrailing) {
                if showPause {
                    Button { onPause(); paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .font(.caption).padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
    }
}

#if DEBUG
#Preview("Flipbook") {
    AnimatedPoster(bundleNames: [], photos: PreviewSample.many)
        .padding()
}

#Preview("Single photo") {
    // One photo: no pause button, nothing to cycle through.
    AnimatedPoster(bundleNames: [], photos: [PreviewSample.one])
        .padding()
}
#endif
