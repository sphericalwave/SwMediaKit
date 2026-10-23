//
//  MediaSourceButton.swift
//  SwMediaKit
//
//  The one "attach a photo" button every app uses. The view itself is
//  platform-owned — `iOS/MediaSourceButton+iOS.swift` (Take Photo / Choose
//  from Library / Remove Photo / Cancel dialog) and
//  `macOS/MediaSourceButton+macOS.swift` (menu: Photos, Finder file, Remove). This
//  file holds what both share: the public initializers and how a pick is
//  handed back.
//
//  Two ways to receive a pick:
//  - `onImage` — storage-ready JPEG `Data`, shrunk and re-encoded off the
//    main actor, once per photo. The default; a host app can't persist a
//    full-resolution capture by accident.
//  - `onCapture` + `onLibrary` — the raw camera shot and the raw picker
//    items, for callers with their own crop / video / asset-id pipeline.
//
//  Host apps must declare `NSCameraUsageDescription` in their Info.plist;
//  without it the camera path traps when the system prompts. Photo-library
//  picking needs no permission (PhotosPicker runs out of process).
//

import SwiftUI
import PhotosUI

/// Which camera Take Photo opens with. The user can still flip it in the
/// system camera; ignored on macOS.
public enum PreferredCamera: Sendable {
    case rear
    case front
}

/// How a finished pick reaches the caller.
enum MediaSourceDelivery {
    /// Cropped (unless `crop` is `.none`), then shrunk + re-encoded JPEG,
    /// one call per photo.
    case storage(maxPixel: CGFloat, quality: CGFloat, crop: PhotoCrop, onImage: (Data) -> Void)
    /// Full-resolution camera JPEG / Finder file, and library items untouched — no crop
    /// step (use `photoCropQueue` for one).
    case raw(onCapture: (Data) -> Void, onLibrary: ([PhotosPickerItem]) -> Void)
}

/// Everything about a `MediaSourceButton` except its label.
struct MediaSourceConfig {
    var matching: PHPickerFilter
    /// Library picks per trip; 0 means no limit.
    var selectionLimit: Int
    /// Offers Remove Photo when set.
    var onRemove: (() -> Void)?
    var preferredCamera: PreferredCamera = .rear
    /// Take Photo opens the framed camera (see `cameraFrame`) rather than
    /// the system one.
    var squareCamera: Bool = true
    var delivery: MediaSourceDelivery

    var maxSelectionCount: Int? { selectionLimit > 0 ? selectionLimit : nil }

    /// The crop step the view should run picks through.
    var crop: PhotoCrop {
        if case let .storage(_, _, crop, _) = delivery { return crop }
        return .none
    }

    /// The frame the camera's viewfinder shows and cuts the shot to, or nil
    /// for the full-frame system camera: the crop's own ratio, square for
    /// `.square`/`.free` and raw picks, none when `squareCamera` is off or
    /// the crop is `.none` (scans and OCR keep the whole frame).
    var cameraFrame: CropShape? {
        guard squareCamera else { return nil }
        switch delivery {
        case .raw:
            return .square
        case let .storage(_, _, crop, _):
            switch crop {
            case .none: return nil
            case .square, .free: return .square
            case let .ratio(w, h): return .ratio(w, h)
            }
        }
    }

    /// Hands back a camera shot. Call once the camera has dismissed — a crop
    /// step presented while it's still on screen gets dropped. `enqueueCrop`
    /// queues a photo for the view's crop step; a `framed` shot was already
    /// cut to `cameraFrame` (and could be tightened) in the camera, so it
    /// skips that step.
    @MainActor func deliverCapture(_ data: Data, framed: Bool = false, enqueueCrop: @escaping ([Data]) -> Void) {
        switch delivery {
        case let .raw(onCapture, _):
            onCapture(data)
        case .storage:
            if crop == .none || framed { deliverStored(data) } else { enqueueCrop([data]) }
        }
    }

    @MainActor func deliverLibrary(_ items: [PhotosPickerItem], enqueueCrop: @escaping ([Data]) -> Void) {
        switch delivery {
        case let .raw(_, onLibrary):
            onLibrary(items)
        case .storage:
            Task {
                var loaded: [Data] = []
                for item in items {
                    guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
                    loaded.append(raw)
                }
                guard !loaded.isEmpty else { return }
                if crop == .none { loaded.forEach(deliverStored) } else { enqueueCrop(loaded) }
            }
        }
    }

    /// Shrinks and re-encodes a picked or cropped photo, then hands it back.
    @MainActor func deliverStored(_ data: Data) {
        guard case let .storage(maxPixel, quality, _, onImage) = delivery else { return }
        Task {
            onImage(await Self.reencoded(data, maxPixel: maxPixel, quality: quality))
        }
    }

    /// Shrinks and re-encodes off the main actor.
    private static func reencoded(_ raw: Data, maxPixel: CGFloat, quality: CGFloat) async -> Data {
        await Task.detached(priority: .userInitiated) {
            PlatformImage.reencodedForStorage(data: raw, maxPixel: maxPixel, quality: quality)
        }.value
    }
}

public extension MediaSourceButton {
    /// Delivers storage-ready photos.
    /// - Parameters:
    ///   - maxPixel: largest edge, in pixels, of the stored image.
    ///   - quality: JPEG quality of the stored image.
    ///   - selectionLimit: how many library photos one trip through the picker
    ///     may return. 1 (the default) dismisses on the first tap; higher lets
    ///     the picker stay up until Add; 0 means no limit.
    ///   - crop: the crop step each photo goes through before `onImage` —
    ///     square by default; `.none` for scans/OCR where the whole frame
    ///     matters.
    ///   - preferredCamera: which camera Take Photo opens with.
    ///   - squareCamera: Take Photo shows a live viewfinder framed to the
    ///     crop (square by default) with the outside dimmed, takes the photo
    ///     already cut to that frame, and offers a pinch to tighten it before
    ///     Use Photo — so camera shots skip the separate crop step. `false`
    ///     opens the full-frame system camera. Ignored on macOS and when
    ///     `crop` is `.none`.
    ///   - onRemove: when set, the button also offers Remove Photo.
    ///   - onImage: receives storage-ready JPEG data on the main actor, once
    ///     per photo, in the order the picker returned them.
    init(maxPixel: CGFloat = 1600,
         quality: CGFloat = 0.82,
         selectionLimit: Int = 1,
         crop: PhotoCrop = .square,
         preferredCamera: PreferredCamera = .rear,
         squareCamera: Bool = true,
         onRemove: (() -> Void)? = nil,
         onImage: @escaping (Data) -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.config = MediaSourceConfig(
            matching: .images, selectionLimit: selectionLimit, onRemove: onRemove,
            preferredCamera: preferredCamera, squareCamera: squareCamera,
            delivery: .storage(maxPixel: maxPixel, quality: quality, crop: crop, onImage: onImage))
        self.label = label
    }

    /// Delivers raw picks, for callers that crop, take videos, or track
    /// library asset ids themselves.
    /// - Parameters:
    ///   - matching: what the library offers (`.images`, or images + videos).
    ///     The camera always takes stills.
    ///   - onCapture: a full-resolution still from outside the Photos library
    ///     — the camera's JPEG on iOS (once the camera has gone), a Finder
    ///     file's data on macOS (Choose File…).
    ///   - squareCamera: Take Photo shows the square framed camera, so
    ///     `onCapture` gets a square shot; `false` for the full-frame system
    ///     camera (scans, screenshots of text). Ignored on macOS.
    ///   - onLibrary: the picked library items, in picker order.
    init(matching: PHPickerFilter = .images,
         selectionLimit: Int = 1,
         preferredCamera: PreferredCamera = .rear,
         squareCamera: Bool = true,
         onRemove: (() -> Void)? = nil,
         onCapture: @escaping (Data) -> Void,
         onLibrary: @escaping ([PhotosPickerItem]) -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.config = MediaSourceConfig(
            matching: matching, selectionLimit: selectionLimit, onRemove: onRemove,
            preferredCamera: preferredCamera, squareCamera: squareCamera,
            delivery: .raw(onCapture: onCapture, onLibrary: onLibrary))
        self.label = label
    }
}

public extension MediaSourceButton where Label == SwiftUI.Label<Text, Image> {
    /// Convenience for the common `Label(title, systemImage:)` case.
    init(_ title: String = "Add Photo",
         systemImage: String = "photo.badge.plus",
         maxPixel: CGFloat = 1600,
         quality: CGFloat = 0.82,
         selectionLimit: Int = 1,
         crop: PhotoCrop = .square,
         preferredCamera: PreferredCamera = .rear,
         squareCamera: Bool = true,
         onRemove: (() -> Void)? = nil,
         onImage: @escaping (Data) -> Void) {
        self.init(maxPixel: maxPixel, quality: quality, selectionLimit: selectionLimit,
                  crop: crop, preferredCamera: preferredCamera, squareCamera: squareCamera,
                  onRemove: onRemove, onImage: onImage) {
            SwiftUI.Label(title, systemImage: systemImage)
        }
    }
}

#if DEBUG
private struct MediaSourceButtonPreview: View {
    @State private var photo: Data?

    var body: some View {
        Form {
            Section("Photo") {
                if let photo, let image = PlatformImage.downsampled(data: photo, maxPixel: 264) {
                    Image(platformImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                // Where there's no camera and nothing to remove — previews
                // included — this goes straight to the library.
                MediaSourceButton(photo == nil ? "Add Photo" : "Change Photo",
                                  onRemove: photo == nil ? nil : { photo = nil }) { photo = $0 }
            }
        }
    }
}

#Preview("In a Form") {
    MediaSourceButtonPreview()
}

#Preview("Custom label") {
    MediaSourceButton { _ in } label: {
        Image(systemName: "camera.fill")
            .font(.title2)
            .padding()
            .background(.tint, in: Circle())
            .foregroundStyle(.white)
    }
}
#endif
