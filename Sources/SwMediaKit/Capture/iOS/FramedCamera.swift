//
//  FramedCamera.swift
//  SwMediaKit
//
//  The camera `MediaSourceButton` opens by default: a live viewfinder with
//  the frame (square unless the crop says otherwise) cut out of a dimmed
//  preview, so what's inside the frame is the photo. The shot is cut to the
//  frame straight away, then shown for review — pinch and drag tighten the
//  crop, Retake goes back, Use Photo hands it over. No separate crop screen.
//  Rear lenses show as Camera-app zoom buttons (.5 / 1× / 2×) above the
//  shutter; it opens on the last one used (see `CameraLensSet.initial`).
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
    var preferredLens: CameraLens = .wide
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
        .task { await camera.start(position: preferredCamera == .front ? .front : .back, preferredLens: preferredLens) }
        .onDisappear { camera.stop() }
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = geo.size
            let insets = geo.safeAreaInsets
            // Clear of the close button above and the shutter (and lens
            // buttons) below.
            let bottom: CGFloat = camera.lenses.offersChoice ? 200 : 140
            let area = CGRect(x: 0, y: insets.top + 64,
                              width: size.width,
                              height: max(0, size.height - insets.top - insets.bottom - 64 - bottom))
            let frame = CameraFraming.viewfinder(aspect: shape.aspect(for: .zero), in: area, margin: 12)
            ZStack {
                if camera.state == .running {
                    CameraPreview(session: camera.session, deviceID: camera.deviceID)
                        .blur(radius: camera.switching ? 16 : 0)
                        .animation(.easeInOut(duration: 0.2), value: camera.switching)
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

            if camera.lenses.offersChoice {
                lensButtons
                    .opacity(camera.lens == nil ? 0 : 1)
                    .allowsHitTesting(camera.lens != nil)
                    .accessibilityHidden(camera.lens == nil)
                    .padding(.bottom, 16)
            }

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
                    Button { Task { await camera.flip() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel("Switch Camera")
                    .disabled(camera.state != .running || processing || camera.switching || !camera.canFlip)
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, insets.bottom + 28)
        }
        .foregroundStyle(.white)
    }

    /// The Camera app's zoom row: small round buttons on a dark capsule, the
    /// current lens larger and yellow. Hidden (space kept) on the front camera.
    private var lensButtons: some View {
        HStack(spacing: 2) {
            ForEach(camera.lenses.lenses, id: \.self) { lens in
                let selected = lens == camera.lens
                Button { Task { await camera.select(lens) } } label: {
                    Text(camera.lenses.title(of: lens, selected: selected))
                        .font(.system(size: selected ? 13 : 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? .yellow : .white)
                        .frame(width: selected ? 38 : 30, height: selected ? 38 : 30)
                        .background(.black.opacity(0.5), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(camera.lenses.accessibilityLabel(of: lens))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .background(.black.opacity(0.25), in: Capsule())
        .animation(.snappy(duration: 0.2), value: camera.lens)
        .disabled(camera.state != .running || processing || camera.switching)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lens")
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
    /// The rear lenses on offer; empty until `start`.
    private(set) var lenses = CameraLensSet(available: [])
    /// True while the camera changes lens or side.
    private(set) var switching = false
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var rearDevices: [CameraLens: AVCaptureDevice] = [:]
    /// The rear lens to come back to from the front camera.
    private var rearLens: CameraLens?
    private let lensMemory = CameraLensMemory()
    private var pending: CheckedContinuation<Data?, Never>?
    /// Session work stays off the main thread; `startRunning` blocks.
    private let queue = DispatchQueue(label: "SwMediaKit.FramedCamera")

    /// The rear lens in use; nil on the front camera.
    var lens: CameraLens? {
        guard let device = input?.device, device.position == .back else { return nil }
        return CameraLens(device.deviceType)
    }

    /// Changes whenever the camera does, so the preview can re-orient.
    var deviceID: String? { input?.device.uniqueID }

    func start(position: AVCaptureDevice.Position, preferredLens: CameraLens) async {
        var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard allowed else {
            state = .denied
            return
        }
        (rearDevices, lenses) = Self.rearLenses()
        rearLens = lenses.initial(remembered: lensMemory.lens, preferred: preferredLens)
        let lensDevice = position == .back ? rearLens.flatMap { rearDevices[$0] } : nil
        // A lens that won't open falls back to 1×, without a word.
        guard let input = lensDevice.flatMap({ try? AVCaptureDeviceInput(device: $0) })
                ?? (Self.device(at: position) ?? Self.device(at: .back)).flatMap({ try? AVCaptureDeviceInput(device: $0) }) else {
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

    func flip() async {
        guard let current = input else { return }
        let next = current.device.position == .front
            ? rearLens.flatMap { rearDevices[$0] } ?? Self.device(at: .back)
            : Self.device(at: .front)
        guard let next else { return }
        await switchInput(to: next)
    }

    /// Switches to `lens` and remembers it for next time.
    func select(_ lens: CameraLens) async {
        guard lens != self.lens, let device = rearDevices[lens] else { return }
        if await switchInput(to: device) {
            rearLens = lens
            lensMemory.lens = lens
        }
    }

    /// Swaps the camera on the session queue, keeping the old one if the new
    /// one won't go in. True when it switched.
    @discardableResult
    private func switchInput(to device: AVCaptureDevice) async -> Bool {
        guard let current = input, !switching,
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        switching = true
        let switched = await run { session in
            session.beginConfiguration()
            session.removeInput(current)
            let fits = session.canAddInput(newInput)
            session.addInput(fits ? newInput : current)
            session.commitConfiguration()
            return fits
        }
        if switched { input = newInput }
        switching = false
        return switched
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

    private func run<T>(_ work: @escaping (AVCaptureSession) -> T) async -> T {
        let session = session
        return await withCheckedContinuation { (done: CheckedContinuation<T, Never>) in
            queue.async {
                done.resume(returning: work(session))
            }
        }
    }

    /// Every rear lens by kind, and the set the buttons offer. The virtual
    /// cameras are only asked for so the telephoto's zoom can be read off
    /// their switch-over factors.
    private static func rearLenses() -> ([CameraLens: AVCaptureDevice], CameraLensSet) {
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera,
                          .builtInTripleCamera, .builtInDualCamera],
            mediaType: .video, position: .back).devices
        var devices: [CameraLens: AVCaptureDevice] = [:]
        for device in found {
            if let lens = CameraLens(device.deviceType), devices[lens] == nil { devices[lens] = device }
        }
        func switchOvers(_ type: AVCaptureDevice.DeviceType) -> [CGFloat]? {
            found.first { $0.deviceType == type }?
                .virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        }
        let zoom = CameraLensSet.telephotoZoom(triple: switchOvers(.builtInTripleCamera),
                                               dual: switchOvers(.builtInDualCamera))
        return (devices, CameraLensSet(available: Array(devices.keys), telephotoZoom: zoom))
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
    /// The camera feeding it; a new one gets a new, unrotated connection.
    let deviceID: String?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        view.upright()
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.upright()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

        /// Portrait, the way the phone is held.
        func upright() {
            if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

extension CameraLens {
    init?(_ type: AVCaptureDevice.DeviceType) {
        switch type {
        case .builtInUltraWideCamera: self = .ultraWide
        case .builtInWideAngleCamera: self = .wide
        case .builtInTelephotoCamera: self = .telephoto
        default: return nil
        }
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
