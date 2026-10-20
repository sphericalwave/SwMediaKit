//
//  PhotoCrop.swift
//  SwMediaKit
//
//  The crop step every picked photo goes through by default: pan and pinch
//  the photo inside a frame, then Use Photo. The crop is cut from the
//  original pixels (orientation applied), never from the on-screen size.
//
//  The step is platform-owned — `iOS/PhotoCropScreen+iOS.swift` (full-screen,
//  navigation bar) and `macOS/PhotoCropScreen+macOS.swift` (sheet with a
//  button bar). This file holds the shapes, the transform and the cut.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Whether picked photos get a crop step, and its frame.
public enum PhotoCrop: Hashable, Sendable {
    /// No crop step — the photo is used as picked. For OCR/scan input.
    case none
    /// Locked 1:1 frame.
    case square
    /// Locked `width:height` frame, e.g. `.ratio(4, 3)`.
    case ratio(CGFloat, CGFloat)
    /// Opens on the photo's own shape; Original, Square, 4:5, 4:3 or 16:9
    /// can be chosen in the crop step.
    case free

    /// The frames offered, the first being where the step opens.
    var shapes: [CropShape] {
        switch self {
        case .none: []
        case .square: [.square]
        case let .ratio(w, h): [.ratio(w, h)]
        case .free: [.original, .square, .ratio(4, 5), .ratio(4, 3), .ratio(16, 9)]
        }
    }
}

/// One crop frame shape.
enum CropShape: Hashable {
    case original
    case square
    case ratio(CGFloat, CGFloat)

    var name: String {
        switch self {
        case .original: "Original"
        case .square: "Square"
        case let .ratio(w, h): "\(Int(w)):\(Int(h))"
        }
    }

    /// Width over height for a photo of `imageSize`.
    func aspect(for imageSize: CGSize) -> CGFloat {
        switch self {
        case .original:
            imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        case .square:
            1
        case let .ratio(w, h):
            h > 0 ? w / h : 1
        }
    }

    /// The largest frame of this shape that fits in `box`.
    func frame(for imageSize: CGSize, in box: CGSize) -> CGSize {
        let aspect = aspect(for: imageSize)
        guard box.width > 0, box.height > 0 else { return .zero }
        return box.width / box.height > aspect
            ? CGSize(width: box.height * aspect, height: box.height)
            : CGSize(width: box.width, height: box.width / aspect)
    }
}

/// Pan and zoom of a photo inside its crop frame. `offset` is in points of
/// `frame`; `scale` is on top of the aspect-fill fit (1 = just covers it).
struct CropTransform: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    /// The on-screen frame the offset is measured against.
    var frame: CGSize = .zero

    /// Pulls the photo back so it still covers the whole frame.
    func clamped(image: CGSize) -> CropTransform {
        let s = max(1, scale)
        let fill = image.width > 0 && image.height > 0
            ? max(frame.width / image.width, frame.height / image.height) : 1
        let maxX = max(0, (image.width * fill * s - frame.width) / 2)
        let maxY = max(0, (image.height * fill * s - frame.height) / 2)
        return CropTransform(scale: s,
                             offset: CGSize(width: min(max(offset.width, -maxX), maxX),
                                            height: min(max(offset.height, -maxY), maxY)),
                             frame: frame)
    }
}

/// Decoding, cutting and encoding — all off the main actor.
enum CropImage {
    /// The full-resolution image with its EXIF orientation applied, so pixel
    /// rows match what's shown.
    static func upright(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
    }

    /// The part of `image` inside the crop frame, at full resolution.
    static func cut(_ image: CGImage, transform: CropTransform) -> CGImage? {
        let pixels = CGSize(width: image.width, height: image.height)
        let t = transform.clamped(image: pixels)
        guard t.frame.width > 0, t.frame.height > 0 else { return nil }
        // Frame points per pixel once fitted and zoomed.
        let k = max(t.frame.width / pixels.width, t.frame.height / pixels.height) * t.scale
        let width = t.frame.width / k
        let height = t.frame.height / k
        let rect = CGRect(x: pixels.width / 2 - t.offset.width / k - width / 2,
                          y: pixels.height / 2 - t.offset.height / k - height / 2,
                          width: width, height: height)
            .integral
            .intersection(CGRect(origin: .zero, size: pixels))
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }

    static func jpeg(_ image: CGImage, quality: CGFloat = 0.95) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

/// The crop frame with pan and pinch, and no chrome. Shared by both
/// platforms' crop screens.
struct CropEditor: View {
    let image: CGImage
    let shape: CropShape
    @Binding var transform: CropTransform

    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    private var pixels: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        GeometryReader { geo in
            let box = CGSize(width: geo.size.width * 0.92, height: geo.size.height * 0.92)
            let frame = shape.frame(for: pixels, in: box)
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(transform.scale)
                .offset(transform.offset)
                .clipped()
                .overlay { CropGrid() }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            transform.offset = CGSize(width: baseOffset.width + value.translation.width,
                                                      height: baseOffset.height + value.translation.height)
                        }
                        .onEnded { _ in settle() }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { value in
                                transform.scale = max(1, baseScale * value.magnification)
                            }
                            .onEnded { _ in settle() })
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { transform.frame = frame }
                .onChange(of: frame) { _, newFrame in
                    transform = CropTransform(frame: newFrame)
                    syncBase()
                }
        }
        .onChange(of: shape) {
            transform = CropTransform(frame: transform.frame)
            syncBase()
        }
    }

    private func settle() {
        withAnimation(.easeOut(duration: 0.2)) { transform = transform.clamped(image: pixels) }
        syncBase()
    }

    private func syncBase() {
        baseScale = transform.scale
        baseOffset = transform.offset
    }
}

/// Rule-of-thirds grid over the frame.
private struct CropGrid: View {
    var body: some View {
        ZStack {
            HStack {
                ForEach(1...2, id: \.self) { _ in
                    Rectangle().fill(.white.opacity(0.7)).frame(width: 1).frame(maxWidth: .infinity)
                }
            }
            VStack {
                ForEach(1...2, id: \.self) { _ in
                    Rectangle().fill(.white.opacity(0.7)).frame(height: 1).frame(maxHeight: .infinity)
                }
            }
            Rectangle().strokeBorder(.white, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Decoded photo + chosen shape + transform for one crop step, shared by
/// both platforms' screens.
@MainActor @Observable
final class CropSession {
    let data: Data
    let shapes: [CropShape]
    var shape: CropShape
    var transform = CropTransform()
    private(set) var image: CGImage?
    private(set) var unreadable = false
    private(set) var cropping = false

    init(data: Data, crop: PhotoCrop) {
        self.data = data
        self.shapes = crop.shapes.isEmpty ? [.original] : crop.shapes
        self.shape = shapes[0]
    }

    func decode() async {
        let data = data
        let decoded = await Task.detached(priority: .userInitiated) { CropImage.upright(data) }.value
        image = decoded
        unreadable = decoded == nil
    }

    /// The cropped JPEG; falls back to the photo as picked if it can't be cut.
    func crop() async -> Data {
        guard let image else { return data }
        cropping = true
        defer { cropping = false }
        let transform = transform
        let cut = await Task.detached(priority: .userInitiated) { () -> Data? in
            CropImage.cut(image, transform: transform).flatMap { CropImage.jpeg($0) }
        }.value
        return cut ?? data
    }
}

/// A photo waiting for its crop step.
struct PendingCrop: Identifiable {
    let id = UUID()
    let data: Data
}

/// Runs each photo appended to `queue` through the crop step, in order.
struct PhotoCropQueue: ViewModifier {
    @Binding var queue: [Data]
    let crop: PhotoCrop
    let onCropped: (Data) -> Void

    @State private var pending: [PendingCrop] = []
    /// Photos already through the step in this batch, for "Photo 2 of 3".
    @State private var done = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: queue) { _, items in
                guard !items.isEmpty else { return }
                pending += items.map { PendingCrop(data: $0) }
                queue = []
            }
            .cropPresentation(item: Binding(
                get: { pending.first },
                // Only the screen's own buttons end a step (a full-screen
                // cover / Mac sheet has no swipe-away), so nothing to do here.
                set: { _ in }
            )) { item in
                PhotoCropScreen(data: item.data, crop: crop,
                                position: done + 1, total: done + pending.count) { finish($0) }
                    .id(item.id)
            }
    }

    private func finish(_ cropped: Data?) {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
        done = pending.isEmpty ? 0 : done + 1
        if let cropped { onCropped(cropped) }
    }
}

public extension View {
    /// Shows the crop step for each photo appended to `queue` (which it
    /// empties), one after another, and hands back each cropped JPEG at full
    /// resolution. Skipped photos are dropped. `MediaSourceButton` does this
    /// itself; use this when picks reach you raw (`onCapture`/`onLibrary`).
    func photoCropQueue(_ queue: Binding<[Data]>, crop: PhotoCrop = .square,
                        onCropped: @escaping (Data) -> Void) -> some View {
        modifier(PhotoCropQueue(queue: queue, crop: crop, onCropped: onCropped))
    }
}
