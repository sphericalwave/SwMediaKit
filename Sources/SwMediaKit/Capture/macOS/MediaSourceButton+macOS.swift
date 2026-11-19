//
//  MediaSourceButton+macOS.swift
//  SwMediaKit
//
//  macOS half: no camera, so the button is a menu — Choose from Photos…,
//  Choose File… (Finder), and Remove Photo when offered. A Finder file takes
//  the same path a camera shot does on iOS: crop step and storage re-encode,
//  or `onCapture` in raw mode.
//
//  With `.deleteOriginalsAfterImport($isOn)` set on the button (or above it)
//  the menu also shows a "Delete Original After Import" checkmark. While on,
//  a Finder file goes to the Trash once it's been read, and a Photos pick
//  goes to Recently Deleted once it's loaded — both recoverable. Photos asks
//  for library access and confirms the delete itself.
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
    @Environment(\.deleteOriginalsAfterImport) private var deleteOriginals

    public var body: some View {
        Menu {
            Button("Choose from Photos…") { showPhotos = true }
            Button("Choose File…") { showFiles = true }
            if let deleteOriginals {
                Toggle("Delete Original After Import", isOn: deleteOriginals)
            }
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
                      matching: config.matching,
                      // The shared library fills in `itemIdentifier`, which
                      // deleting the original needs. Picking still needs no
                      // permission.
                      photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            config.deliverLibrary(items) { cropQueue += $0 }
            if deleteOriginals?.wrappedValue == true {
                Task { await PhotosOriginals.delete(items) }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image],
                      allowsMultipleSelection: config.selectionLimit != 1) { result in
            guard case let .success(urls) = result else { return }
            let limited = config.selectionLimit > 0 ? Array(urls.prefix(config.selectionLimit)) : urls
            let trash = deleteOriginals?.wrappedValue == true
            Task {
                for data in await Self.read(limited, trashAfterReading: trash) {
                    config.deliverCapture(data) { cropQueue += $0 }
                }
            }
        }
        .photoCropQueue($cropQueue, crop: config.crop, onCropped: config.deliverStored)
    }

    /// Reads the chosen files off the main actor. They're security-scoped in
    /// the sandbox; unreadable ones are skipped. With `trashAfterReading`, a
    /// file that was read moves to the Trash (needs the host's
    /// user-selected-files entitlement to be read-write; a failed move leaves
    /// the file where it was).
    private static func read(_ urls: [URL], trashAfterReading: Bool) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
                if trashAfterReading { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                return data
            }
        }.value
    }
}
#endif
