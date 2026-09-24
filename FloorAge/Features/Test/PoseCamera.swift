import AVFoundation
import SwiftUI
import Vision

/// The front camera plus Apple's on-device body pose detection. Frames are analysed on the phone
/// and thrown away: nothing is recorded, saved or sent.
final class PoseCamera: NSObject, ObservableObject {
    enum Status: Equatable { case off, starting, running, denied, unavailable }

    /// Scripted movement for the Debug demo screens (no camera needed).
    enum Demo { case chairStand, balance, reach }

    @Published private(set) var status = Status.off
    @Published private(set) var pose: BodyPose?
    /// Size of the (portrait) frames, to line the skeleton up with the preview.
    @Published private(set) var frameSize = CGSize(width: 720, height: 1280)
    /// Called on the main thread with every detected pose.
    var onPose: ((BodyPose) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "floorage.posecamera")
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private let demo: Demo?
    private var demoTimer: Timer?
    private var demoStart = Date()

    init(demo: Demo? = nil) {
        self.demo = demo
    }

    var isDemo: Bool { demo != nil }

    func start() {
        guard status == .off || status == .denied else { return }
        if let demo {
            startDemo(demo)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        demoTimer?.invalidate()
        demoTimer = nil
        pose = nil
        guard status != .off else { return }
        status = .off
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func run() {
        status = .starting
        queue.async { [self] in
            if !configured {
                guard configure() else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                configured = true
            }
            session.startRunning()
            DispatchQueue.main.async { if self.status == .starting { self.status = .running } }
        }
    }

    /// Front camera, portrait, mirrored like a mirror so moving left moves left on screen.
    private func configure() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return true
    }

    private func publish(_ pose: BodyPose?, size: CGSize? = nil) {
        if let size, size != frameSize { frameSize = size }
        self.pose = pose
        if let pose { onPose?(pose) }
    }

    // MARK: - Demo

    private func startDemo(_ demo: Demo) {
        status = .running
        demoStart = Date()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince(self.demoStart)
            let pose: BodyPose = switch demo {
            case .chairStand:
                // Sit, stand, sit… about one stand every 2.4 seconds.
                .sample(rise: (1 - cos(t / 2.4 * 2 * .pi)) / 2)
            case .balance:
                .sample(lift: t > 1 ? min((t - 1) * 2, 1) : 0)
            case .reach:
                .sample(fold: min(t / 3, 1), wristDepth: 0.25)
            }
            self.publish(pose)
        }
    }
}

extension PoseCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let joints: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose), (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let size = CMSampleBufferGetImageBuffer(sampleBuffer).map {
            CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
        }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        var pose: BodyPose?
        if (try? handler.perform([request])) != nil,
           let observation = request.results?.first,
           let points = try? observation.recognizedPoints(.all) {
            var joints: [BodyJoint: CGPoint] = [:]
            for (name, joint) in Self.joints {
                if let point = points[name], point.confidence > 0.3 { joints[joint] = point.location }
            }
            if !joints.isEmpty { pose = BodyPose(joints: joints) }
        }
        DispatchQueue.main.async { self.publish(pose, size: size) }
    }
}

// MARK: - Views

/// The live camera with the tracked skeleton drawn on top. The whole frame is shown (not cropped),
/// so people can check their feet are in view.
struct CameraStage: View {
    @ObservedObject var camera: PoseCamera
    let feature: Feature
    let hint: String

    var body: some View {
        ZStack {
            Color.black
            if camera.isDemo {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
                    .aspectRatio(camera.frameSize, contentMode: .fit)
            } else {
                CameraPreview(session: camera.session)
            }
            SkeletonOverlay(pose: camera.pose, frameSize: camera.frameSize, feature: feature)
            VStack {
                Spacer()
                Label(hint, systemImage: camera.pose?.legsVisible == true ? "figure.stand" : "viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.bottom, 14)
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Bones and joints over the camera image, mapped the same way the preview fills the frame.
private struct SkeletonOverlay: View {
    let pose: BodyPose?
    let frameSize: CGSize
    let feature: Feature

    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftWrist), (.rightShoulder, .rightWrist),
        (.neck, .leftHip), (.neck, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let scale = min(size.width / frameSize.width, size.height / frameSize.height)
            let drawn = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
            func place(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * drawn.width - (drawn.width - size.width) / 2,
                        y: (1 - p.y) * drawn.height - (drawn.height - size.height) / 2)
            }
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = pose[a], let pb = pose[b] else { continue }
                path.move(to: place(pa))
                path.addLine(to: place(pb))
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: feature.colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))
            for point in pose.joints.values {
                let p = place(point)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
