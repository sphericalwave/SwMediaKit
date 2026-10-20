//
//  MediaSourceButton+macOS.swift
//  SwMediaKit
//
//  macOS half: no camera, so the button opens the photo library directly and
//  Remove Photo, when offered, is a row of its own.
//

#if os(macOS)
import SwiftUI
import PhotosUI

public struct MediaSourceButton<Label: View>: View {
    let config: MediaSourceConfig
    let label: () -> Label

    @State private var picked: [PhotosPickerItem] = []
    @State private var cropQueue: [Data] = []

    public var body: some View {
        PhotosPicker(selection: $picked,
                     maxSelectionCount: config.maxSelectionCount,
                     matching: config.matching) {
            label()
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            config.deliverLibrary(items) { cropQueue += $0 }
        }
        .photoCropQueue($cropQueue, crop: config.crop, onCropped: config.deliverStored)
        if let onRemove = config.onRemove {
            Button("Remove Photo", role: .destructive, action: onRemove)
        }
    }
}
#endif
