//
//  CameraPicker.swift
//  SwMediaKit
//
//  The system camera, wrapped for SwiftUI. `UIImagePickerController` with
//  `.camera` gives us the shutter, retake, flash, zoom, front/back toggle and
//  the permission prompt for free — the alternative is an `AVCaptureSession`
//  plus a hand-rolled shutter UI, which is where every app-local camera in this
//  codebase has gone wrong.
//
//  iOS only. Callers should present this through `MediaSourceButton` rather
//  than directly.
//

#if os(iOS)
import SwiftUI
import UIKit

public struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured photo, or `nil` if the user cancelled.
    /// Delivers full-resolution JPEG data — compress before persisting.
    let onCapture: (Data?) -> Void
    let preferredCamera: PreferredCamera

    public init(preferredCamera: PreferredCamera = .rear, onCapture: @escaping (Data?) -> Void) {
        self.preferredCamera = preferredCamera
        self.onCapture = onCapture
    }

    /// `false` on the simulator and on any device without a camera, in which
    /// case presenting this view would show an empty picker.
    public static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        if preferredCamera == .front, UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    public final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                                    UINavigationControllerDelegate {
        private let onCapture: (Data?) -> Void

        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            // JPEG at 1.0 here is not the storage encoding — `MediaSourceButton`
            // runs the result through `reencodedForStorage`. This just gets the
            // capture out of `UIImage` without throwing away detail first.
            onCapture(image?.jpegData(compressionQuality: 1.0))
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
#endif

#if os(iOS) && DEBUG
// Only renders on a real device — `UIImagePickerController(.camera)` has no
// simulator or preview-canvas implementation, so the canvas stays black.
#Preview("Device only") {
    CameraPicker { _ in }
        .ignoresSafeArea()
}
#endif
