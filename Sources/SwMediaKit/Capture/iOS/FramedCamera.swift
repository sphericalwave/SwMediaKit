//
//  FramedCamera.swift
//  SwMediaKit
//
//  The camera `MediaSourceButton` opens by default: a live viewfinder with
//  the frame (square unless the crop says otherwise) cut out of a dimmed
//  preview, so what's inside the frame is the photo. The shot is cut to the
//  frame straight away, then shown for review — pinch and drag tighten the
//  crop, Retake goes back, Use Photo hands it over. No separate crop screen.
//
//  Built on `AVCaptureSession` because `UIImagePickerController` can't frame
//  its viewfinder or its output.
//

#if os(iOS)
import SwiftUI
import AVFoundation

struct FramedCamera: View {
    let shape: CropShape
    let preferredCamera: PreferredCamera
    /// The framed JPEG at full resolution, or nil when cancelled.
    let onFinish: (Data?) -> Void

    @State private var camera = FramedCameraSession()
    /// The shot being reviewed; nil while the viewfinder is live.
    @State private var review: CropSession?
    @State private var processing = false
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let review {
                FramedShotReview(session: review,
                                 onRetake: { self.review = nil },
                                 onUse: { onFinish($0) })
            } else {
                viewfinder
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await camera.start(position: preferredCamera == .front ? .front : .back) }
        .onDisappear { camera.stop() }
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = geo.size
            let insets = geo.safeAreaInsets
            // Clear of the close button above and the shutter below.
            let area = CGRect(x: 0, y: insets.top + 64,
                              width: size.width,
                              height: max(0, size.height - insets.top - insets.bottom - 64 - 140))
            let frame = CameraFraming.viewfinder(aspect: shape.aspect(for: .zero), in: area, margin: 12)
            ZStack {
                if camera.state == .running {
                    CameraPreview(session: camera.session)
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: size))
                        path.addRect(frame)
                    }
                    .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    Rectangle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                } else {
                    unavailableMessage
                        .frame(width: size.width, height: size.height)
                }
                if flash {
                    Color.white.opacity(0.7).allowsHitTesting(false)
                }
                controls(insets: insets, frame: frame, previewSize: size)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var unavailableMessage: some View {
        switch camera.state {
        case .denied:
            ContentUnavailableView {
                Label("Camera access is off", systemImage: "camera.fill")
            } description: {
                Text("Allow camera access in Settings to take a photo.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .unavailable:
            ContentUnavailableView("No camera available", systemImage: "camera.badge.ellipsis")
        case .starting, .running:
            ProgressView().tint(.white)
        }
    }

    private func controls(insets: EdgeInsets, frame: CGRect, previewSize: CGSize) -> some View {
        VStack {
            HStack {
                Button { onFinish(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 8)

            Spacer()

            ZStack {
                Button { shoot(frame: frame, previewSize: previewSize) } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 62, height: 62)
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        if processing { ProgressView().tint(.black) }
                    }
                }
                .accessibilityLabel("Take Photo")
                .disabled(camera.state != .running || processing)

                HStack {
                    Spacer()
                    Button { camera.flip() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel("Switch Camera")
                    .disabled(camera.state != .running || processing || !camera.canFlip)
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, insets.bottom + 28)
        }
        .foregroundStyle(.white)
    }

    private func shoot(frame: CGRect, previewSize: CGSize) {
        processing = true
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task {
            withAnimation(.easeIn(duration: 0.2)) { flash = false }
            let shot = await camera.capture()
            let framed = await Task.detached(priority: .userInitiated) {
                shot.flatMap { FramedShot.cut($0, frame: frame, previewSize: previewSize) }
            }.value
            if let framed {
                let session = CropSession(data: framed, shape: shape)
                await session.decode()
                review = session
            }
            processing = false
        }
    }
}

/// The framed shot, already the right shape: Use Photo as is, or pinch and
/// drag to tighten it first.
private struct FramedShotReview: View {
    @Bindable var session: CropSession
    let onRetake: () -> Void
    let onUse: (Data) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let image = session.image {
                CropEditor(image: image, shape: session.shape, transform: $session.transform)
            } else {
                Spacer()
            }
            Text("Pinch to tighten the crop")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.vertical, 12)
            HStack {
                Button("Retake", action: onRetake)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 88, minHeight: 50)
                Spacer()
                Button {
                    Task { onUse(await session.crop()) }
                } label: {
                    Group {
                        if session.cropping {
                            ProgressView().tint(.black)
                        } else {
                            Text("Use Photo").font(.body.weight(.bold))
                        }
                    }
                    .frame(minWidth: 120, minHeight: 50)
                }
                .foregroundStyle(.black)
                .background(.white, in: Capsule())
                .disabled(session.cropping)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}

/// Cutting a captured photo to the viewfinder's frame.
enum FramedShot {
    /// The part of `data` that was inside `frame` on a preview of
    /// `previewSize`, as a full-resolution JPEG.
    static func cut(_ data: Data, frame: CGRect, previewSize: CGSize) -> Data? {
        guard let image = CropImage.upright(data) else { return nil }
        let rect = CameraFraming.pixelRect(of: frame, previewSize: previewSize,
                                           imageSize: CGSize(width: image.width, height: image.height))
        guard !rect.isEmpty, let cut = image.cropping(to: rect) else { return nil }
        return CropImage.jpeg(cut)
    }
}

/// Owns the capture session: permission, the chosen camera, one still at a time.
@MainActor @Observable
final class FramedCameraSession: NSObject {
    enum State { case starting, running, denied, unavailable }

    private(set) var state: State = .starting
    private(set) var canFlip = false
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var pending: CheckedContinuation<Data?, Never>?
    /// Session work stays off the main thread; `startRunning` blocks.
    private let queue = DispatchQueue(label: "SwMediaKit.FramedCamera")

    func start(position: AVCaptureDevice.Position) async {
        var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard allowed else {
            state = .denied
            return
        }
        guard let device = Self.device(at: position) ?? Self.device(at: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }
        canFlip = Self.device(at: .front) != nil && Self.device(at: .back) != nil
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        self.input = input
        await run { $0.startRunning() }
        state = session.isRunning ? .running : .unavailable
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
        finish(nil)
    }

    func flip() {
        guard let current = input else { return }
        let next: AVCaptureDevice.Position = current.device.position == .front ? .back : .front
        guard let device = Self.device(at: next), let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.removeInput(current)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        } else {
            session.addInput(current)
        }
        session.commitConfiguration()
    }

    /// A full-resolution still, upright for a portrait-held phone; nil on failure.
    func capture() async -> Data? {
        guard state == .running, pending == nil else { return nil }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return await withCheckedContinuation { continuation in
            pending = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func finish(_ data: Data?) {
        pending?.resume(returning: data)
        pending = nil
    }

    private func run(_ work: @escaping (AVCaptureSession) -> Void) async {
        let session = session
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                work(session)
                done.resume()
            }
        }
    }

    private static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

extension FramedCameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor in self.finish(data) }
    }
}

/// The live feed, aspect-filled — the mapping `CameraFraming.pixelRect` assumes.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }
}

extension CropSession {
    /// A review of an already-framed shot, locked to `shape`.
    convenience init(data: Data, shape: CropShape) {
        let crop: PhotoCrop
        switch shape {
        case .square: crop = .square
        case let .ratio(w, h): crop = .ratio(w, h)
        case .original: crop = .none
        }
        self.init(data: data, crop: crop)
    }
}
#endif

#if os(iOS) && DEBUG
// Only shows a live feed on a real device; the simulator has no camera.
#Preview("Device only") {
    FramedCamera(shape: .square, preferredCamera: .rear) { _ in }
}
#endif
