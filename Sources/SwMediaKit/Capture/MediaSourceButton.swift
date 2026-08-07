//
//  MediaSourceButton.swift
//  SwMediaKit
//
//  One button for "attach a photo", from either the camera or the photo
//  library. Both paths land on `reencodedForStorage` off the main actor, so
//  `onImage` always hands back storage-ready JPEG `Data` — a host app never
//  persists a full-resolution capture by accident.
//
//  Host apps must declare `NSCameraUsageDescription` in their Info.plist;
//  without it the camera path traps when the system prompts. Photo-library
//  picking needs no permission (PhotosPicker runs out of process).
//

import SwiftUI
import PhotosUI

public struct MediaSourceButton<Label: View>: View {
    private let maxPixel: CGFloat
    private let quality: CGFloat
    private let selectionLimit: Int
    private let onImage: (Data) -> Void
    private let label: () -> Label

    @State private var showDialog = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []

    /// - Parameters:
    ///   - maxPixel: largest edge, in pixels, of the stored image.
    ///   - quality: JPEG quality of the stored image.
    ///   - selectionLimit: how many library photos one trip through the picker
    ///     may return. 1 (the default) dismisses on the first tap; higher lets
    ///     the picker stay up until Add; 0 means no limit.
    ///   - onImage: receives storage-ready JPEG data on the main actor, once
    ///     per photo, in the order the picker returned them.
    public init(maxPixel: CGFloat = 1600,
                quality: CGFloat = 0.82,
                selectionLimit: Int = 1,
                onImage: @escaping (Data) -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        self.maxPixel = maxPixel
        self.quality = quality
        self.selectionLimit = selectionLimit
        self.onImage = onImage
        self.label = label
    }

    /// True where a camera exists — false on the simulator, on macOS, and on
    /// camera-less devices. Those cases go straight to the library, with no
    /// dead "Take Photo" row.
    private var cameraAvailable: Bool {
        #if os(iOS)
        CameraPicker.isAvailable
        #else
        false
        #endif
    }

    public var body: some View {
        Button {
            if cameraAvailable { showDialog = true } else { showLibrary = true }
        } label: {
            label()
        }
        .confirmationDialog("Add Photo", isPresented: $showDialog, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked,
                      maxSelectionCount: selectionLimit > 0 ? selectionLimit : nil,
                      matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                picked = []
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self) {
                        await deliver(raw)
                    }
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                guard let data else { return }
                Task { await deliver(data) }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    /// Shrinks and re-encodes off the main actor, then hands the result back on it.
    private func deliver(_ raw: Data) async {
        let maxPixel = maxPixel
        let quality = quality
        let stored = await Task.detached(priority: .userInitiated) {
            PlatformImage.reencodedForStorage(data: raw, maxPixel: maxPixel, quality: quality)
        }.value
        onImage(stored)
    }
}

public extension MediaSourceButton where Label == SwiftUI.Label<Text, Image> {
    /// Convenience for the common `Label(title, systemImage:)` case.
    init(_ title: String = "Add Photo",
         systemImage: String = "photo.badge.plus",
         maxPixel: CGFloat = 1600,
         quality: CGFloat = 0.82,
         selectionLimit: Int = 1,
         onImage: @escaping (Data) -> Void) {
        self.init(maxPixel: maxPixel, quality: quality,
                  selectionLimit: selectionLimit, onImage: onImage) {
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
                // Where there's no camera — previews included — this goes
                // straight to the library instead of offering a dead row.
                MediaSourceButton(photo == nil ? "Add Photo" : "Change Photo") { photo = $0 }
                if photo != nil {
                    Button("Remove Photo", role: .destructive) { photo = nil }
                }
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
