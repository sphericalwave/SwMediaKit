//
//  PhotoCropScreen+macOS.swift
//  SwMediaKit
//
//  macOS half of the crop step: a sheet with the frame on black, the shape
//  menu when there's a choice, and Cancel/Skip + Use Photo along the bottom.
//

#if os(macOS)
import SwiftUI

public struct PhotoCropScreen: View {
    private let total: Int
    private let position: Int
    /// The cropped JPEG, or nil when the photo was skipped.
    private let onFinish: (Data?) -> Void

    @State private var session: CropSession

    /// - Parameters:
    ///   - position, total: "Photo 2 of 3" when cropping a batch.
    public init(data: Data, crop: PhotoCrop = .square, position: Int = 1, total: Int = 1,
                onFinish: @escaping (Data?) -> Void) {
        self.position = position
        self.total = total
        self.onFinish = onFinish
        _session = State(initialValue: CropSession(data: data, crop: crop))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image = session.image {
                    CropEditor(image: image, shape: session.shape, transform: $session.transform)
                } else if session.unreadable {
                    ContentUnavailableView("Can't open this photo", systemImage: "photo.badge.exclamationmark",
                                           description: Text(total > 1 ? "Skip it to carry on with the rest." : "Cancel and pick another."))
                        .foregroundStyle(.white)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            HStack {
                Text(total > 1 ? "Photo \(position) of \(total)" : "Crop Photo")
                    .font(.headline)
                if session.shapes.count > 1 {
                    Picker("Shape", selection: $session.shape) {
                        ForEach(session.shapes, id: \.self) { Text($0.name).tag($0) }
                    }
                    .fixedSize()
                    .disabled(session.image == nil)
                }
                Spacer()
                Button(total > 1 ? "Skip" : "Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(session.cropping)
                if session.cropping {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Use Photo") {
                        Task { onFinish(await session.crop()) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.image == nil)
                }
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 520)
        .task { await session.decode() }
    }
}

extension View {
    /// How the crop step is shown on macOS.
    func cropPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, content: content)
    }
}

#if DEBUG
#Preview("Square") {
    PhotoCropScreen(data: PreviewSample.one) { _ in }
}

#Preview("Free, batch") {
    PhotoCropScreen(data: PreviewSample.one, crop: .free, position: 2, total: 3) { _ in }
}
#endif
#endif
