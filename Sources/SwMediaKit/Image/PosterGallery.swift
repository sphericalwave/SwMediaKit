//
//  PosterGallery.swift
//  SwMediaKit
//
//  Paged gallery of bundle-named images (resolved from the host app's
//  Bundle.main). Shows page dots when there is more than one image.
//

import SwiftUI

public struct PosterGallery: View {
    let names: [String]
    var contentMode: ContentMode
    var cornerRadius: CGFloat

    public init(names: [String], contentMode: ContentMode = .fit, cornerRadius: CGFloat = 0) {
        self.names = names
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if names.isEmpty {
            EmptyView()
        } else {
            TabView {
                ForEach(names, id: \.self) { n in
                    Image(n)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: names.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif
            .aspectRatio(4.0 / 3.0, contentMode: contentMode)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
