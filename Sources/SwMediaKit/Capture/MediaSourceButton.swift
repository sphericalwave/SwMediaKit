//
//  MediaSourceButton.swift
//  SwMediaKit
//
//  The one "attach a photo" button every app uses. The view itself is
//  platform-owned — `iOS/MediaSourceButton+iOS.swift` (Take Photo / Choose
//  from Library / Remove Photo / Cancel dialog) and
//  `macOS/MediaSourceButton+macOS.swift` (library picker + Remove row). This
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

/// How a finished pick reaches the caller.
enum MediaSourceDelivery {
    /// Shrunk + re-encoded JPEG, one call per photo.
    case storage(maxPixel: CGFloat, quality: CGFloat, onImage: (Data) -> Void)
    /// Full-resolution camera JPEG, and library items untouched.
    case raw(onCapture: (Data) -> Void, onLibrary: ([PhotosPickerItem]) -> Void)
}

/// Everything about a `MediaSourceButton` except its label.
struct MediaSourceConfig {
    var matching: PHPickerFilter
    /// Library picks per trip; 0 means no limit.
    var selectionLimit: Int
    /// Offers Remove Photo when set.
    var onRemove: (() -> Void)?
    var delivery: MediaSourceDelivery

    var maxSelectionCount: Int? { selectionLimit > 0 ? selectionLimit : nil }

    /// Hands back a camera shot. Call once the camera has dismissed — a crop
    /// sheet presented while it's still on screen gets dropped.
    @MainActor func deliverCapture(_ data: Data) {
        switch delivery {
        case let .raw(onCapture, _):
            onCapture(data)
        case let .storage(maxPixel, quality, onImage):
            Task {
                onImage(await Self.reencoded(data, maxPixel: maxPixel, quality: quality))
            }
        }
    }

    @MainActor func deliverLibrary(_ items: [PhotosPickerItem]) {
        switch delivery {
        case let .raw(_, onLibrary):
            onLibrary(items)
        case let .storage(maxPixel, quality, onImage):
            Task {
                for item in items {
                    guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
                    onImage(await Self.reencoded(raw, maxPixel: maxPixel, quality: quality))
                }
            }
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
    ///   - onRemove: when set, the button also offers Remove Photo.
    ///   - onImage: receives storage-ready JPEG data on the main actor, once
    ///     per photo, in the order the picker returned them.
    init(maxPixel: CGFloat = 1600,
         quality: CGFloat = 0.82,
         selectionLimit: Int = 1,
         onRemove: (() -> Void)? = nil,
         onImage: @escaping (Data) -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.config = MediaSourceConfig(
            matching: .images, selectionLimit: selectionLimit, onRemove: onRemove,
            delivery: .storage(maxPixel: maxPixel, quality: quality, onImage: onImage))
        self.label = label
    }

    /// Delivers raw picks, for callers that crop, take videos, or track
    /// library asset ids themselves.
    /// - Parameters:
    ///   - matching: what the library offers (`.images`, or images + videos).
    ///     The camera always takes stills.
    ///   - onCapture: the camera's full-resolution JPEG, once the camera has
    ///     gone. Never called on macOS.
    ///   - onLibrary: the picked library items, in picker order.
    init(matching: PHPickerFilter = .images,
         selectionLimit: Int = 1,
         onRemove: (() -> Void)? = nil,
         onCapture: @escaping (Data) -> Void,
         onLibrary: @escaping ([PhotosPickerItem]) -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.config = MediaSourceConfig(
            matching: matching, selectionLimit: selectionLimit, onRemove: onRemove,
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
         onRemove: (() -> Void)? = nil,
         onImage: @escaping (Data) -> Void) {
        self.init(maxPixel: maxPixel, quality: quality, selectionLimit: selectionLimit,
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
