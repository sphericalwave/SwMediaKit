//
//  ImageCompressionTests.swift
//  SwMediaKitTests
//
//  Landmine guard: proves the compression path actually shrinks a large image.
//  If `reencodedForStorage` / `downsampled` ever regress to a pass-through
//  no-op (the bug that shipped full-res photos and froze the UI), these fail.
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SwMediaKit

final class ImageCompressionTests: XCTestCase {

    /// Builds a `width`×`height` opaque bitmap encoded as PNG (worst case for
    /// size — no lossy compression), to stand in for a full-res photo pick.
    private func largePNG(width: Int, height: Int) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // A gradient-ish fill so the PNG doesn't trivially RLE to nothing.
        for y in stride(from: 0, to: height, by: 4) {
            ctx.setFillColor(red: Double(y % 255) / 255.0, green: 0.3, blue: 0.6, alpha: 1)
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 4))
        }
        let cg = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func pixelSize(of data: Data) throws -> (w: Int, h: Int) {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let h = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        return (w, h)
    }

    func testReencodedForStorageDownscalesAndShrinks() throws {
        let input = try largePNG(width: 4000, height: 3000)
        let output = PlatformImage.reencodedForStorage(data: input, maxPixel: 1600)

        // Largest edge is capped.
        let size = try pixelSize(of: output)
        XCTAssertLessThanOrEqual(max(size.w, size.h), 1600,
                                 "largest edge must be downscaled to <= maxPixel")

        // Output is meaningfully smaller than the raw input, and under a hard
        // ceiling — this is the assertion that fails if compression no-ops.
        XCTAssertLessThan(output.count, input.count)
        XCTAssertLessThan(output.count, 800 * 1024,
                          "a 1600px JPEG must stay well under 800KB")
    }

    func testDownsampledCapsLargestEdge() throws {
        let input = try largePNG(width: 4000, height: 3000)
        let img = try XCTUnwrap(PlatformImage.downsampled(data: input, maxPixel: 200))
        #if os(iOS)
        let longest = max(img.size.width, img.size.height) * img.scale
        #else
        let longest = max(img.size.width, img.size.height)
        #endif
        // Thumbnail generation targets the cap; allow a small rounding margin.
        XCTAssertLessThanOrEqual(longest, 200 + 1)
    }
}
