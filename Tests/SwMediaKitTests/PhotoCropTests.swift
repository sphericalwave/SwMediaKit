//
//  PhotoCropTests.swift
//  SwMediaKitTests
//
//  The crop is cut from the original pixels: these pin the rect it cuts for a
//  given frame, pan and zoom, so a regression to on-screen-size crops (the
//  old ~330 px bug) or an off-centre cut shows up.
//

import XCTest
import CoreGraphics
@testable import SwMediaKit

final class PhotoCropTests: XCTestCase {

    private func image(width: Int, height: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    func testSquareFrameFitsBox() {
        let frame = CropShape.square.frame(for: CGSize(width: 4000, height: 3000),
                                           in: CGSize(width: 300, height: 500))
        XCTAssertEqual(frame, CGSize(width: 300, height: 300))
    }

    func testOriginalFrameKeepsPhotoAspect() {
        let frame = CropShape.original.frame(for: CGSize(width: 4000, height: 2000),
                                             in: CGSize(width: 300, height: 300))
        XCTAssertEqual(frame, CGSize(width: 300, height: 150))
    }

    func testUnzoomedSquareCutIsCentredAtFullResolution() throws {
        let cut = try XCTUnwrap(CropImage.cut(try image(width: 400, height: 200),
                                              transform: CropTransform(frame: CGSize(width: 100, height: 100))))
        XCTAssertEqual(cut.width, 200)
        XCTAssertEqual(cut.height, 200)
    }

    func testZoomHalvesTheCut() throws {
        let cut = try XCTUnwrap(CropImage.cut(try image(width: 400, height: 200),
                                              transform: CropTransform(scale: 2, frame: CGSize(width: 100, height: 100))))
        XCTAssertEqual(cut.width, 100)
    }

    func testPanIsClampedInsideThePhoto() {
        let t = CropTransform(offset: CGSize(width: 500, height: 500), frame: CGSize(width: 100, height: 100))
            .clamped(image: CGSize(width: 400, height: 200))
        // Fitted width 200 pt in a 100 pt frame → 50 pt of travel each way, none vertically.
        XCTAssertEqual(t.offset, CGSize(width: 50, height: 0))
    }

    func testFreeOffersShapesStartingAtOriginal() {
        XCTAssertEqual(PhotoCrop.free.shapes.first, .original)
        XCTAssertEqual(PhotoCrop.square.shapes, [.square])
        XCTAssertTrue(PhotoCrop.none.shapes.isEmpty)
    }
}
