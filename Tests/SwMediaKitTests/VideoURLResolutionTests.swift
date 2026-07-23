//
//  VideoURLResolutionTests.swift
//  SwMediaKitTests
//
//  Covers the testable half of the video player: the missing-resource path
//  that drives the "coming soon" fallback. (Positive resolution is a thin
//  wrapper over Foundation's bundle lookup and needs no dedicated test.)
//

import XCTest
@testable import SwMediaKit

final class VideoURLResolutionTests: XCTestCase {

    func testMissingResourceReturnsNil() {
        let bundle = Bundle(for: Self.self)
        // Nothing is bundled under this name -> nil -> "coming soon" fallback.
        XCTAssertNil(bundledMediaURL(resource: "definitely-not-a-real-video",
                                     fileExtension: "m4v", bundle: bundle))
    }

    func testMissingResourceInMainBundleReturnsNil() {
        XCTAssertNil(bundledMediaURL(resource: "definitely-not-a-real-video"))
    }
}
