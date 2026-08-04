//
//  InstructionalVideoSheet.swift
//  SwMediaKit
//
//  Full-screen chrome (NavigationStack + inline title + Done) around a
//  BundledVideoPlayer. Use for a tap-to-open instructional video, optionally
//  seeked to a chapter timecode.
//

import SwiftUI

public struct InstructionalVideoSheet: View {
    let title: String
    let resource: String
    let startSeconds: Double?

    @Environment(\.dismiss) private var dismiss

    public init(title: String, resource: String, startSeconds: Double? = nil) {
        self.title = title
        self.resource = resource
        self.startSeconds = startSeconds
    }

    public var body: some View {
        NavigationStack {
            BundledVideoPlayer(resource: resource, startSeconds: startSeconds)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#if DEBUG
#Preview("Sheet chrome") {
    Color.clear.sheet(isPresented: .constant(true)) {
        InstructionalVideoSheet(title: "Thoracic Roll", resource: "nonexistent")
    }
}
#endif
