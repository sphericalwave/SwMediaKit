//
//  CameraLensTests.swift
//  SwMediaKitTests
//
//  Which lens buttons the framed camera shows for a given phone, which one it
//  opens on, and how they're labelled.
//

import XCTest
@testable import SwMediaKit

final class CameraLensTests: XCTestCase {

    // iPhone 12: ultra-wide + wide. iPhone 13 Pro: all three. iPhone SE: wide only.
    private let twelve = CameraLensSet(available: [.wide, .ultraWide])
    private let thirteenPro = CameraLensSet(available: [.telephoto, .wide, .ultraWide], telephotoZoom: 3)
    private let se = CameraLensSet(available: [.wide])

    func testLensesAreWidestFirst() {
        XCTAssertEqual(twelve.lenses, [.ultraWide, .wide])
        XCTAssertEqual(thirteenPro.lenses, [.ultraWide, .wide, .telephoto])
    }

    func testButtonsOnlyWithAChoice() {
        XCTAssertTrue(twelve.offersChoice)
        XCTAssertFalse(se.offersChoice)
        XCTAssertFalse(CameraLensSet(available: []).offersChoice)
    }

    func testOpensOnPreferredLens() {
        XCTAssertEqual(twelve.initial(remembered: nil, preferred: .ultraWide), .ultraWide)
        XCTAssertEqual(twelve.initial(remembered: nil, preferred: .wide), .wide)
    }

    func testRememberedLensBeatsPreference() {
        XCTAssertEqual(twelve.initial(remembered: .wide, preferred: .ultraWide), .wide)
        XCTAssertEqual(thirteenPro.initial(remembered: .telephoto, preferred: .ultraWide), .telephoto)
    }

    func testMissingLensFallsBackToWide() {
        // No ultra-wide: preference quietly becomes 1×.
        XCTAssertEqual(se.initial(remembered: nil, preferred: .ultraWide), .wide)
        // Remembered from a phone that had a tele: preference, then 1×.
        XCTAssertEqual(twelve.initial(remembered: .telephoto, preferred: .ultraWide), .ultraWide)
        XCTAssertEqual(se.initial(remembered: .telephoto, preferred: .ultraWide), .wide)
    }

    func testNoWideFallsBackToWhateverThereIs() {
        XCTAssertEqual(CameraLensSet(available: [.ultraWide]).initial(remembered: nil, preferred: .wide), .ultraWide)
        XCTAssertNil(CameraLensSet(available: []).initial(remembered: .wide, preferred: .wide))
    }

    func testTitlesMatchTheCameraApp() {
        XCTAssertEqual(twelve.title(of: .ultraWide, selected: false), ".5")
        XCTAssertEqual(twelve.title(of: .ultraWide, selected: true), "0.5×")
        XCTAssertEqual(twelve.title(of: .wide, selected: false), "1×")
        XCTAssertEqual(thirteenPro.title(of: .telephoto, selected: true), "3×")
        XCTAssertEqual(CameraLensSet(available: [.telephoto], telephotoZoom: 2.5).title(of: .telephoto, selected: false), "2.5×")
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(twelve.accessibilityLabel(of: .ultraWide), "0.5 times")
        XCTAssertEqual(twelve.accessibilityLabel(of: .wide), "1 times")
        XCTAssertEqual(thirteenPro.accessibilityLabel(of: .telephoto), "3 times")
    }

    func testTelephotoZoomFromSwitchOvers() {
        XCTAssertEqual(CameraLensSet.telephotoZoom(triple: [2, 6], dual: [3]), 3)
        XCTAssertEqual(CameraLensSet.telephotoZoom(triple: [2, 5], dual: nil), 2.5)
        XCTAssertEqual(CameraLensSet.telephotoZoom(triple: nil, dual: [2]), 2)
        XCTAssertNil(CameraLensSet.telephotoZoom(triple: nil, dual: nil))
    }

    func testTelephotoZoomRoundsToHalfStepsAndDefaultsToTwo() {
        XCTAssertEqual(CameraLensSet(available: [.telephoto], telephotoZoom: 2.96).telephotoZoom, 3)
        XCTAssertEqual(CameraLensSet(available: [.telephoto]).telephotoZoom, 2)
        XCTAssertEqual(CameraLensSet(available: [.telephoto], telephotoZoom: 0.8).telephotoZoom, 2)
    }

    func testMemoryRoundTrips() throws {
        let suite = "CameraLensTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = CameraLensMemory(defaults: defaults)
        XCTAssertNil(memory.lens)
        memory.lens = .ultraWide
        XCTAssertEqual(CameraLensMemory(defaults: defaults).lens, .ultraWide)
        defaults.set("fisheye", forKey: CameraLensMemory.key)
        XCTAssertNil(memory.lens)
    }
}
