//
//  CameraFramingTests.swift
//  SwMediaKitTests
//
//  The framed camera cuts the shot to what was inside the viewfinder: these
//  pin the viewfinder's placement and the preview-to-pixel mapping, and which
//  pickers get the framed camera at all.
//

import XCTest
import PhotosUI
@testable import SwMediaKit

final class CameraFramingTests: XCTestCase {

    func testSquareViewfinderFitsTheNarrowSideAndCentres() {
        let area = CGRect(x: 0, y: 100, width: 390, height: 600)
        let frame = CameraFraming.viewfinder(aspect: 1, in: area, margin: 12)
        XCTAssertEqual(frame.width, 366, accuracy: 0.01)
        XCTAssertEqual(frame.height, 366, accuracy: 0.01)
        XCTAssertEqual(frame.midX, area.midX, accuracy: 0.01)
        XCTAssertEqual(frame.midY, area.midY, accuracy: 0.01)
    }

    func testRatioViewfinderKeepsItsAspect() {
        let frame = CameraFraming.viewfinder(aspect: 4.0 / 3.0, in: CGRect(x: 0, y: 0, width: 300, height: 600))
        XCTAssertEqual(frame.width / frame.height, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(frame.width, 300, accuracy: 0.01)
    }

    /// A 3024×4032 portrait shot aspect-filled into a 390×844 screen: the
    /// photo's height fits, its sides overflow. A centred square across the
    /// screen's width maps to a centred square of photo pixels.
    func testCentredSquareMapsToCentredSquareOfPixels() {
        let preview = CGSize(width: 390, height: 844)
        let image = CGSize(width: 3024, height: 4032)
        let frame = CGRect(x: 12, y: 239, width: 366, height: 366)
        let rect = CameraFraming.pixelRect(of: frame, previewSize: preview, imageSize: image)

        let k = 844.0 / 4032.0
        XCTAssertEqual(rect.width, 366 / k, accuracy: 2)
        XCTAssertEqual(rect.height, 366 / k, accuracy: 2)
        XCTAssertEqual(rect.midX, image.width / 2, accuracy: 2)
        XCTAssertEqual(rect.midY, (239 + 183) / k, accuracy: 2)
    }

    func testFrameOutsideThePhotoIsClipped() {
        let rect = CameraFraming.pixelRect(of: CGRect(x: -50, y: -50, width: 100, height: 100),
                                           previewSize: CGSize(width: 100, height: 100),
                                           imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    // MARK: - Which pickers get the framed camera

    private func storage(_ crop: PhotoCrop, squareCamera: Bool = true) -> MediaSourceConfig {
        MediaSourceConfig(matching: .images, selectionLimit: 1, onRemove: nil, squareCamera: squareCamera,
                          delivery: .storage(maxPixel: 1600, quality: 0.8, crop: crop, onImage: { _ in }))
    }

    func testSquareIsTheDefaultFrame() {
        XCTAssertEqual(storage(.square).cameraFrame, .square)
        XCTAssertEqual(storage(.free).cameraFrame, .square)
    }

    func testRatioCropFramesTheCameraToThatRatio() {
        XCTAssertEqual(storage(.ratio(4, 3)).cameraFrame, .ratio(4, 3))
    }

    func testScansKeepTheFullFrameCamera() {
        XCTAssertNil(storage(.none).cameraFrame)
    }

    func testOptOutKeepsTheSystemCamera() {
        XCTAssertNil(storage(.square, squareCamera: false).cameraFrame)
    }

    func testRawPicksAreSquareUnlessOptedOut() {
        let raw = MediaSourceConfig(matching: .images, selectionLimit: 1, onRemove: nil,
                                    delivery: .raw(onCapture: { _ in }, onLibrary: { _ in }))
        XCTAssertEqual(raw.cameraFrame, .square)
        var optedOut = raw
        optedOut.squareCamera = false
        XCTAssertNil(optedOut.cameraFrame)
    }
}
