//
//  BundledVideoPlayer.swift
//  SwMediaKit
//
//  Lifecycle-correct player for a bundled video resource. The AVPlayer is
//  created once in `onAppear` (never inside `body`, which would leak a new
//  player every re-render) and paused in `onDisappear`. Shows a "coming soon"
//  placeholder when the resource isn't in the bundle yet.
//

import SwiftUI
import AVKit

/// Resolves a bundled media resource to a URL. Factored out so the lookup +
/// missing-resource fallback are unit-testable without an AVPlayer.
public func bundledMediaURL(resource: String, fileExtension: String = "m4v",
                            bundle: Bundle = .main) -> URL? {
    bundle.url(forResource: resource, withExtension: fileExtension)
}

public struct BundledVideoPlayer: View {
    let resource: String
    let fileExtension: String
    let startSeconds: Double?
    let autoplay: Bool
    let bundle: Bundle

    @State private var player: AVPlayer?

    public init(resource: String, fileExtension: String = "m4v",
                startSeconds: Double? = nil, autoplay: Bool = false,
                bundle: Bundle = .main) {
        self.resource = resource
        self.fileExtension = fileExtension
        self.startSeconds = startSeconds
        self.autoplay = autoplay
        self.bundle = bundle
    }

    public var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ContentUnavailableView(
                    "Video coming soon",
                    systemImage: "play.slash",
                    description: Text("This instructional video hasn't been added yet.")
                )
            }
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    private func load() {
        guard player == nil,
              let url = bundledMediaURL(resource: resource, fileExtension: fileExtension,
                                        bundle: bundle)
        else { return }
        let p = AVPlayer(url: url)
        if let start = startSeconds, start > 0 {
            p.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        player = p
        if autoplay { p.play() }
    }
}

#if DEBUG
// The package bundles no video, so this exercises the missing-resource
// placeholder — which is the branch worth eyeballing anyway.
#Preview("Missing resource") {
    BundledVideoPlayer(resource: "nonexistent")
}
#endif
