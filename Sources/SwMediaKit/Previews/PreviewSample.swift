//
//  PreviewSample.swift
//  SwMediaKit
//
//  Sample photo `Data` for previews. This package ships no asset catalog, and
//  the bundle-name views resolve against the *host app's* `Bundle.main`, which
//  a package preview doesn't have — so previews drive the `photos:` /
//  `photoData:` paths with images generated here instead.
//
//  CoreGraphics + ImageIO only, so it works identically on iOS and macOS.
//  DEBUG-only: none of this ships in a release build.
//

#if DEBUG
import Foundation
import CoreGraphics
import ImageIO

enum PreviewSample {
    /// A flat-tinted JPEG with an off-centre dot, so successive frames in a
    /// flipbook are visibly different from one another.
    static func photo(hue: Double, side: Int = 400) -> Data {
        let (r, g, b) = rgb(hue: hue, saturation: 0.45, value: 0.95)
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }

        let size = CGFloat(side)
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Dot orbits with the hue so each sample reads as a distinct frame.
        let angle = hue * 2 * .pi
        let radius = size * 0.22
        let dot = CGRect(
            x: size / 2 + cos(angle) * size * 0.18 - radius,
            y: size / 2 + sin(angle) * size * 0.18 - radius,
            width: radius * 2, height: radius * 2
        )
        let (dr, dg, db) = rgb(hue: hue, saturation: 0.85, value: 0.55)
        ctx.setFillColor(red: dr, green: dg, blue: db, alpha: 1)
        ctx.fillEllipse(in: dot)

        guard let image = ctx.makeImage() else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return out as Data
    }

    /// A single sample, for the one-image cases.
    static var one: Data { photo(hue: 0.55) }

    /// Four samples, enough to see a flipbook actually cycling.
    static var many: [Data] {
        [0.02, 0.30, 0.55, 0.80].map { photo(hue: $0) }
    }

    private static func rgb(hue: Double, saturation: Double,
                            value: Double) -> (CGFloat, CGFloat, CGFloat) {
        let h = (hue.truncatingRemainder(dividingBy: 1) * 6)
        let i = Int(h)
        let f = h - Double(i)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (value, t, p)
        case 1: (r, g, b) = (q, value, p)
        case 2: (r, g, b) = (p, value, t)
        case 3: (r, g, b) = (p, q, value)
        case 4: (r, g, b) = (t, p, value)
        default: (r, g, b) = (value, p, q)
        }
        return (CGFloat(r), CGFloat(g), CGFloat(b))
    }
}
#endif
