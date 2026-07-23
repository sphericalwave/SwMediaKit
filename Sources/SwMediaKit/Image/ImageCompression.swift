// Image downsampling + storage re-encoding, shared across apps.
//
// Custom skill photos arrive from the photo picker at full resolution (a 12MP
// HEIC is several MB and inflates to a huge bitmap). Decoding them at native
// size to display at ~80–220pt, or storing them raw, stalls the main thread and
// bloats on-disk data. These helpers do a single ImageIO pass — call them off
// the main actor.
import Foundation
import ImageIO
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public extension PlatformImage {
    /// Plain full-resolution decode. Prefer `downsampled` for display.
    static func from(data: Data) -> PlatformImage? { PlatformImage(data: data) }

    /// Decodes `data` downsampled so its largest edge is ~`maxPixel` px, in a
    /// single ImageIO pass — it never inflates the full-resolution bitmap.
    /// Falls back to a plain decode if ImageIO can't build a thumbnail.
    static func downsampled(data: Data, maxPixel: CGFloat) -> PlatformImage? {
        guard let src = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return PlatformImage(data: data) }

        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else {
            return PlatformImage(data: data)
        }
        #if os(iOS)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: .zero)
        #endif
    }

    /// Downscales `data` to a `maxPixel` largest edge and re-encodes it as JPEG
    /// for on-disk storage. Shrinks picker images before they hit persistence so
    /// faulting + decoding stay cheap. One ImageIO pass, no intermediate
    /// `PlatformImage`. Returns the input unchanged on any failure.
    static func reencodedForStorage(data: Data, maxPixel: CGFloat = 1600,
                                    quality: CGFloat = 0.82) -> Data {
        guard let src = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return data }

        let thumbOpts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return data }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, "public.jpeg" as CFString, 1, nil
        ) else { return data }
        CGImageDestinationAddImage(
            dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return data }
        return out as Data
    }
}
