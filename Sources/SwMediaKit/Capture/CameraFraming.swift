//
//  CameraFraming.swift
//  SwMediaKit
//
//  Geometry for the framed camera: where the viewfinder's frame sits on
//  screen, and which pixels of the finished shot lie under it. Kept apart
//  from the iOS camera view so it can be tested on any platform.
//

import CoreGraphics

enum CameraFraming {

    /// The largest frame of `aspect` (width over height) that fits in `area`
    /// less `margin` on every side, centred in it.
    static func viewfinder(aspect: CGFloat, in area: CGRect, margin: CGFloat = 0) -> CGRect {
        let box = area.insetBy(dx: margin, dy: margin)
        guard box.width > 0, box.height > 0, aspect > 0 else { return .zero }
        let size = box.width / box.height > aspect
            ? CGSize(width: box.height * aspect, height: box.height)
            : CGSize(width: box.width, height: box.width / aspect)
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The pixels of an upright photo of `imageSize` that were under `frame`,
    /// when the live preview showed that photo aspect-filled into
    /// `previewSize` (`AVLayerVideoGravity.resizeAspectFill`). `frame` is in
    /// the preview's points.
    static func pixelRect(of frame: CGRect, previewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              previewSize.width > 0, previewSize.height > 0 else { return .zero }
        // Preview points per photo pixel, and where the scaled photo's corner sits.
        let k = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let originX = (previewSize.width - imageSize.width * k) / 2
        let originY = (previewSize.height - imageSize.height * k) / 2
        let rect = CGRect(x: (frame.minX - originX) / k,
                          y: (frame.minY - originY) / k,
                          width: frame.width / k,
                          height: frame.height / k)
        return rect.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
