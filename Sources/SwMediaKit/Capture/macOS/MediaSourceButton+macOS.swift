//
//  MediaSourceButton+macOS.swift
//  SwMediaKit
//
//  macOS half: no camera, so the button is a menu — Choose from Photos…,
//  Choose File… (Finder), and Remove Photo when offered. A Finder file takes
//  the same path a camera shot does on iOS: crop step and storage re-encode,
//  or `onCapture` in raw mode.
//

#if os(macOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct MediaSourceButton<Label: View>: View {
    let config: MediaSourceConfig
    let label: () -> Label

    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var cropQueue: [Data] = []

    public var body: some View {
        Menu {
            Button("Choose from Photos…") { showPhotos = true }
            Button("Choose File…") { showFiles = true }
            if let onRemove = config.onRemove {
                Divider()
                Button("Remove Photo", role: .destructive, action: onRemove)
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .photosPicker(isPresented: $showPhotos, selection: $picked,
                      maxSelectionCount: config.maxSelectionCount,
                      matching: config.matching)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            config.deliverLibrary(items) { cropQueue += $0 }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image],
                      allowsMultipleSelection: config.selectionLimit != 1) { result in
            guard case let .success(urls) = result else { return }
            let limited = config.selectionLimit > 0 ? Array(urls.prefix(config.selectionLimit)) : urls
            Task {
                for data in await Self.read(limited) {
                    config.deliverCapture(data) { cropQueue += $0 }
                }
            }
        }
        .photoCropQueue($cropQueue, crop: config.crop, onCropped: config.deliverStored)
    }

    /// Reads the chosen files off the main actor. They're security-scoped in
    /// the sandbox; unreadable ones are skipped.
    private static func read(_ urls: [URL]) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
                return data
            }
        }.value
    }
}
#endif
