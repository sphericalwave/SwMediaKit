//
//  DataVideoPlayer.swift
//  SwMediaKit
//
//  Playback and thumbnailing for a video stored as raw `Data` (e.g.
//  `.externalStorage` blobs) rather than a bundled or on-disk resource.
//  AVPlayer/AVAssetImageGenerator need a URL, so both write the data to a
//  temp file first.
//

import SwiftUI
import AVKit

/// First-frame thumbnail generated from a video's raw data, with a play
/// glyph overlay so it reads as playable media.
public struct DataVideoThumbnail: View {
    let data: Data
    let size: CGFloat
    let contentMode: ContentMode

    @State private var image: PlatformImage?

    public init(data: Data, size: CGFloat, contentMode: ContentMode = .fill) {
        self.data = data
        self.size = size
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.secondary.opacity(0.15)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: size * 0.3))
                .foregroundStyle(.white)
                .shadow(radius: 2)
        }
        .frame(width: size, height: size)
        .task(id: data) { await generateThumbnail() }
    }

    private func generateThumbnail() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard (try? data.write(to: url)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? await generator.image(at: .zero).image {
            #if os(iOS)
            image = PlatformImage(cgImage: cgImage)
            #else
            image = PlatformImage(cgImage: cgImage, size: .zero)
            #endif
        }
    }
}

/// Writes raw video `Data` to a temp file and plays it. Full-screen chrome
/// with a title and Done button, for use as a `.sheet(item:)` or
/// `.sheet(isPresented:)` destination.
public struct DataVideoPlayerSheet: View {
    let title: String
    let data: Data

    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?

    public init(title: String, data: Data) {
        self.title = title
        self.data = data
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let fileURL {
                    VideoPlayer(player: AVPlayer(url: fileURL))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try? data.write(to: url)
            fileURL = url
        }
    }
}

#if DEBUG
#Preview("Thumbnail fallback") {
    DataVideoThumbnail(data: Data(), size: 88)
}
#endif
