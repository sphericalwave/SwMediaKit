// Cross-platform image type alias shared between iOS and macOS targets.
import SwiftUI
#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

public extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// Wraps a decoded `CGImage` at 1 pt = 1 px (UIImage scale 1 / NSImage pixel size).
    convenience init(decodedCGImage cg: CGImage) {
        #if os(iOS)
        self.init(cgImage: cg)
        #else
        self.init(cgImage: cg, size: .zero)
        #endif
    }

    /// Backing bitmap, if any.
    var backingCGImage: CGImage? {
        #if os(iOS)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}
