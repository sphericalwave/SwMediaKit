//
//  CameraLens.swift
//  SwMediaKit
//
//  The rear lenses the framed camera offers as Camera-app style zoom buttons
//  (.5 / 1× / 2×…), which one it opens on, and remembering the last one
//  picked. Plain logic over a lens list, so it's testable without a camera;
//  the iOS camera feeds it what `AVCaptureDevice.DiscoverySession` finds.
//

import Foundation
import CoreGraphics

/// A rear camera lens, named after the Camera app's zoom buttons.
public enum CameraLens: String, CaseIterable, Sendable {
    /// 0.5×, where the phone has one.
    case ultraWide
    /// 1× — every phone has this.
    case wide
    /// 2×, 2.5×, 3× or 5×, depending on the phone.
    case telephoto
}

/// The rear lenses one phone has, and which the framed camera opens on.
struct CameraLensSet: Equatable {
    /// Widest first, the order the buttons show in.
    let lenses: [CameraLens]
    /// The telephoto's zoom relative to 1×.
    let telephotoZoom: CGFloat

    init(available: [CameraLens], telephotoZoom: CGFloat? = nil) {
        lenses = CameraLens.allCases.filter(available.contains)
        if let telephotoZoom, telephotoZoom > 1 {
            // Nearest half step: 2×, 2.5×, 3×, 5×.
            self.telephotoZoom = (telephotoZoom * 2).rounded() / 2
        } else {
            self.telephotoZoom = 2
        }
    }

    /// Buttons are only worth showing with a choice to make.
    var offersChoice: Bool { lenses.count > 1 }

    /// The lens last used if this phone has it, else the app's preference,
    /// else 1×, else whatever there is; nil with no rear camera.
    func initial(remembered: CameraLens?, preferred: CameraLens) -> CameraLens? {
        [remembered, preferred, .wide].compactMap { $0 }.first(where: lenses.contains) ?? lenses.first
    }

    func zoom(of lens: CameraLens) -> CGFloat {
        switch lens {
        case .ultraWide: return 0.5
        case .wide: return 1
        case .telephoto: return telephotoZoom
        }
    }

    /// Button text the way the Camera app writes it: ".5", "1×", "3×", and
    /// "0.5×" once selected.
    func title(of lens: CameraLens, selected: Bool) -> String {
        let number = Self.format(zoom(of: lens))
        if selected { return number + "×" }
        return number.hasPrefix("0.") ? String(number.dropFirst()) : number + "×"
    }

    /// What VoiceOver reads: "0.5 times".
    func accessibilityLabel(of lens: CameraLens) -> String {
        Self.format(zoom(of: lens)) + " times"
    }

    /// The telephoto's zoom from the virtual cameras' switch-over factors,
    /// which count from each virtual camera's widest lens: the triple
    /// camera's (ultra-wide, wide, tele) are [2, 6] for a 3× tele, the dual
    /// camera's (wide, tele) [2] for a 2×. Nil when neither is there.
    static func telephotoZoom(triple: [CGFloat]?, dual: [CGFloat]?) -> CGFloat? {
        if let triple, triple.count == 2, triple[0] > 0 { return triple[1] / triple[0] }
        return dual?.first
    }

    private static func format(_ zoom: CGFloat) -> String {
        zoom == zoom.rounded() ? String(Int(zoom)) : String(format: "%.1f", Double(zoom))
    }
}

/// The lens last picked, in the host app's own defaults — so per app.
struct CameraLensMemory {
    static let key = "SwMediaKit.FramedCamera.lens"
    var defaults: UserDefaults = .standard

    var lens: CameraLens? {
        get { defaults.string(forKey: Self.key).flatMap(CameraLens.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Self.key) }
    }
}
