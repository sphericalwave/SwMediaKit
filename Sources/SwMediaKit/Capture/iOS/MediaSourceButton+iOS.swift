//
//  MediaSourceButton+iOS.swift
//  SwMediaKit
//
//  iOS half: the standard photo action sheet — Take Photo, Choose from
//  Library, Remove Photo, Cancel. Rows that can't apply are left out (no
//  camera, nothing to remove); with only the library left it goes straight
//  there. Take Photo opens `FramedCamera` (square viewfinder, shot already
//  cropped) unless the config asks for the full-frame system camera.
//

#if os(iOS)
import SwiftUI
import PhotosUI

public struct MediaSourceButton<Label: View>: View {
    let config: MediaSourceConfig
    let label: () -> Label

    @State private var showDialog = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var cameraShot: Data?
    /// Whether `cameraShot` came from the framed camera, already cropped.
    @State private var cameraShotFramed = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var cropQueue: [Data] = []

    public var body: some View {
        Button {
            if CameraPicker.isAvailable || config.onRemove != nil {
                showDialog = true
            } else {
                showLibrary = true
            }
        } label: {
            label()
        }
        .confirmationDialog("Photo", isPresented: $showDialog, titleVisibility: .hidden) {
            if CameraPicker.isAvailable {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showLibrary = true }
            if let onRemove = config.onRemove {
                Button("Remove Photo", role: .destructive, action: onRemove)
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked,
                      maxSelectionCount: config.maxSelectionCount,
                      matching: config.matching)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            config.deliverLibrary(items) { cropQueue += $0 }
        }
        // The shot goes out only once the camera is gone — a crop presented
        // while it's still dismissing gets dropped.
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let shot = cameraShot {
                cameraShot = nil
                config.deliverCapture(shot, framed: cameraShotFramed) { cropQueue += $0 }
            }
        }) {
            if let frame = config.cameraFrame {
                FramedCamera(shape: frame, preferredCamera: config.preferredCamera) { data in
                    cameraShot = data
                    cameraShotFramed = true
                    showCamera = false
                }
            } else {
                CameraPicker(preferredCamera: config.preferredCamera) { data in
                    cameraShot = data
                    cameraShotFramed = false
                    showCamera = false
                }
                .ignoresSafeArea()
            }
        }
        .photoCropQueue($cropQueue, crop: config.crop, onCropped: config.deliverStored)
    }
}
#endif
