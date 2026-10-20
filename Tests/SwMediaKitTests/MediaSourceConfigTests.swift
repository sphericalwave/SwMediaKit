//
//  MediaSourceConfigTests.swift
//  SwMediaKitTests
//
//  The delivery half of `MediaSourceButton`: raw mode passes the shot through
//  untouched, storage mode re-encodes it before handing it back.
//

import XCTest
@testable import SwMediaKit

@MainActor
final class MediaSourceConfigTests: XCTestCase {

    func testSelectionLimitZeroMeansNoLimit() {
        let config = MediaSourceConfig(matching: .images, selectionLimit: 0, onRemove: nil,
                                       delivery: .raw(onCapture: { _ in }, onLibrary: { _ in }))
        XCTAssertNil(config.maxSelectionCount)
        XCTAssertEqual(MediaSourceConfig(matching: .images, selectionLimit: 3, onRemove: nil,
                                         delivery: config.delivery).maxSelectionCount, 3)
    }

    func testRawCaptureIsPassedThroughUnchanged() {
        var received: Data?
        let config = MediaSourceConfig(matching: .images, selectionLimit: 1, onRemove: nil,
                                       delivery: .raw(onCapture: { received = $0 }, onLibrary: { _ in }))
        let shot = Data([1, 2, 3])
        config.deliverCapture(shot)
        XCTAssertEqual(received, shot)
    }

    func testStorageCaptureArrivesAsync() async {
        let delivered = expectation(description: "onImage")
        let config = MediaSourceConfig(
            matching: .images, selectionLimit: 1, onRemove: nil,
            delivery: .storage(maxPixel: 100, quality: 0.8, onImage: { _ in delivered.fulfill() }))
        // Not an image — reencodedForStorage returns it unchanged, but it
        // still goes through the async hop.
        config.deliverCapture(Data([0]))
        await fulfillment(of: [delivered], timeout: 5)
    }
}
