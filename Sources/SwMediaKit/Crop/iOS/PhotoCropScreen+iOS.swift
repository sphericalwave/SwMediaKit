//
//  PhotoCropScreen+iOS.swift
//  SwMediaKit
//
//  iOS half of the crop step: full screen on black, Cancel/Skip and Use Photo
//  in the navigation bar, the shape menu in the bottom bar when there's a
//  choice.
//

#if os(iOS)
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
        NavigationStack {
            Group {
                if let image = session.image {
                    CropEditor(image: image, shape: session.shape, transform: $session.transform)
                } else if session.unreadable {
                    ContentUnavailableView("Can't open this photo", systemImage: "photo.badge.exclamationmark",
                                           description: Text(total > 1 ? "Skip it to carry on with the rest." : "Cancel and pick another."))
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(total > 1 ? "Photo \(position) of \(total)" : "Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarBackground(Color.black, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(total > 1 ? "Skip" : "Cancel") { onFinish(nil) }
                        .disabled(session.cropping)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session.cropping {
                        ProgressView()
                    } else {
                        Button("Use Photo") {
                            Task { onFinish(await session.crop()) }
                        }
                        .bold()
                        .disabled(session.image == nil)
                    }
                }
                if session.shapes.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        Picker(selection: $session.shape) {
                            ForEach(session.shapes, id: \.self) { Text($0.name).tag($0) }
                        } label: {
                            Label("Shape", systemImage: "aspectratio")
                        }
                        .pickerStyle(.menu)
                        .disabled(session.image == nil)
                    }
                }
            }
            .task { await session.decode() }
        }
    }
}

extension View {
    /// How the crop step is shown on iOS.
    func cropPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        fullScreenCover(item: item, content: content)
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
